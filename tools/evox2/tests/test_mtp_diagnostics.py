import importlib.util
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("mtp_diagnostics", ROOT / "tools/evox2/benchmark/mtp_diagnostics.py")
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)


def event(kind, ident, start, end=0, parent="none", domain="server", phase="generation", **extra):
    fields = dict(v=1, kind=kind, id=ident, parent=parent, domain=domain, event="target_evaluation",
                  ctx="0x1", role="target", phase=phase, thread="1", t0_us=start, t1_us=end,
                  elapsed_us=end-start if end else 0, complete=int(bool(end)), rc=0, mode="wall")
    fields.update(extra)
    return "mtp_diag " + " ".join(f"{k}={v}" for k, v in fields.items())


def refused_probe():
    root = dict(domain="memory", phase="unknown", event="seq_rm", seq=0, pos_first=1, pos_last=-1)
    child = dict(domain="memory", phase="unknown", event="seq_rm_recurrent", parent="probe")
    return [event("begin", "probe", 10, **root), event("begin", "recurrent", 20, **child),
            event("end", "recurrent", 20, 30, rc=-1, complete=0, **child),
            event("end", "probe", 10, 40, rc=-1, complete=0, **root),
            "0.34.893.146 I cmn  common_conte: the context does not support partial sequence removal"]


class AccountingTests(unittest.TestCase):
    def test_nested_times_are_not_added_to_coverage(self):
        lines = [event("begin", "outer", 100), event("begin", "child", 120, parent="outer"),
                 event("end", "child", 120, 170, parent="outer"), event("end", "outer", 100, 200)]
        report = parser.summarize(lines, {"GenerationEvalMilliseconds": 0.15})
        self.assertTrue(report["Complete"], report["Issues"])
        self.assertEqual(report["CoveredServerGenerationUs"], 100)
        self.assertEqual(report["ApproximateUncoveredGenerationUs"], 50)
        self.assertEqual(next(e for e in report["Events"] if e["id"] == "outer")["ExclusiveUs"], 50)

    def test_cross_module_memory_role_and_phase(self):
        lines = [event("begin", "register", 1, phase="setup", event="context", mem="0x2", role="draft"),
                 event("end", "register", 1, 2, phase="setup", event="context", mem="0x2", role="draft"),
                 event("begin", "call", 10, role="draft"),
                 event("begin", "layout", 20, domain="memory", phase="unknown", role="unknown", mem="0x2"),
                 event("end", "layout", 20, 30, domain="memory", phase="unknown", role="unknown", mem="0x2"),
                 event("end", "call", 10, 40, role="draft")]
        r = parser.summarize(lines)
        e = next(e for e in r["Events"] if e["id"] == "layout")
        self.assertEqual((e["ResolvedRole"], e["ResolvedPhase"]), ("draft", "generation"))

    def test_interrupted_and_missing_logs(self):
        self.assertFalse(parser.summarize([event("begin", "a", 100)])["Complete"])
        self.assertEqual(parser.summarize([])["Status"], "MissingDiagnostics")

    def test_other_thread_is_not_invented_parent(self):
        lines = [event("begin", "a", 10), event("begin", "b", 20, thread="2", phase="unknown", domain="vulkan"),
                 event("end", "b", 20, 30, thread="2", phase="unknown", domain="vulkan"), event("end", "a", 10, 40)]
        r = parser.summarize(lines)
        self.assertEqual(r["UnmatchedPhaseEvents"], 1)
        self.assertIsNone(next(e for e in r["Events"] if e["id"] == "b")["ResolvedParent"])

    def test_mixed_and_exception_records_remain_explicit(self):
        r = parser.summarize([event("begin", "a", 10, phase="mixed"),
                              event("end", "a", 10, 40, phase="mixed", complete=0)])
        self.assertFalse(r["Complete"])
        self.assertEqual(r["Events"][0]["ResolvedPhase"], "mixed")

    def test_duplicate_and_unsupported_schema(self):
        r = parser.summarize([event("begin", "a", 10), event("begin", "a", 10),
                              event("end", "a", 10, 20), event("begin", "other", 30, v=2)])
        self.assertFalse(r["Complete"])

    def test_startup_capability_refusal_is_recorded_without_failure(self):
        r = parser.summarize(refused_probe())
        self.assertTrue(r["Complete"], r["Issues"])
        self.assertEqual(len(r["ExpectedRefusals"]), 1)
        self.assertEqual(sum(g["ExpectedRefusals"] for g in r["Groups"]), 2)
        self.assertTrue(all(e["rc"] == -1 and e["complete"] == 0 and e["ExpectedRefusal"] for e in r["Events"]))

    def test_unrecognized_or_late_refusal_stays_incomplete(self):
        startup = refused_probe()
        cases = [startup[:-1], [startup[0], startup[1], startup[3], startup[4]],
                 [event("begin", "inference", 1), event("end", "inference", 1, 5)] + startup,
                 [line.replace("pos_first=1", "pos_first=2") for line in startup],
                 [line.replace("thread=1", "thread=2") if "id=recurrent " in line else line for line in startup]]
        for lines in cases:
            r = parser.summarize(lines)
            self.assertFalse(r["Complete"], lines)


class RecoveryTests(unittest.TestCase):
    def fixture(self, root, status="DIAGNOSTIC_INCOMPLETE", exit_code=0, complete_matrix=True):
        child = root / "child"
        child.mkdir()
        (child / "stderr.log").write_text("\n".join(refused_probe()) + "\n", encoding="utf-8")
        result = {"RunId": "run1", "Status": status, "DiagnosticStatus": "Incomplete", "DiagnosticError": "old error",
                  "ExitCode": exit_code, "RunException": None, "GeneratedTokens": 512, "GenerationTokensPerSecond": 19.69}
        (child / "result.json").write_text(json.dumps(result))
        self.csv(child / "summary.csv", {"RunId": "run1", "Status": status, "TG": "19.69"})
        matrix = {"Runs": [{"MatrixRunId": "M001", "ChildRunId": "run1", "ChildRunDirectory": str(child), "MatrixStatus": status}],
                  "Results": [{"MatrixRunId": "M001", "ChildStatus": status, "TG": 19.69}],
                  "RunCountPlanned": 1 if complete_matrix else 2, "RunCountFinished": 1,
                  "Complete": False, "StoppedEarly": True, "StatusCounts": {"OK": 0, "NonOK": 1}}
        (root / "matrix-result.json").write_text(json.dumps(matrix))
        self.csv(root / "matrix-runs.csv", {"MatrixRunId": "M001", "MatrixStatus": status})
        self.csv(root / "matrix-results.csv", {"MatrixRunId": "M001", "ChildStatus": status, "TG": "19.69"})
        return child

    @staticmethod
    def csv(path, row):
        with path.open("w", newline="", encoding="utf-8-sig") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(row))
            writer.writeheader(); writer.writerow(row)

    def test_diagnostic_only_recovery_preserves_metrics_and_updates_all_statuses(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); child = self.fixture(root)
            parser.repair_matrix(root)
            result = json.loads((child / "result.json").read_text())
            self.assertEqual((result["Status"], result["GeneratedTokens"], result["GenerationTokensPerSecond"]), ("OK", 512, 19.69))
            self.assertEqual(result["DiagnosticRecovery"]["PreviousDiagnosticError"], "old error")
            matrix = json.loads((root / "matrix-result.json").read_text())
            self.assertTrue(matrix["Complete"])
            self.assertEqual(matrix["StatusCounts"], {"OK": 1, "NonOK": 0})
            for name, key in (("child/summary.csv", "Status"), ("matrix-runs.csv", "MatrixStatus"), ("matrix-results.csv", "ChildStatus")):
                with (root / name).open(encoding="utf-8-sig", newline="") as f:
                    self.assertEqual(next(csv.DictReader(f))[key], "OK")

    def test_runtime_error_cannot_be_recovered_as_success(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); child = self.fixture(root, exit_code=1)
            with self.assertRaises(ValueError): parser.repair_matrix(root)
            self.assertEqual(json.loads((child / "result.json").read_text())["Status"], "DIAGNOSTIC_INCOMPLETE")

    def test_partially_collected_matrix_cannot_be_marked_complete(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); self.fixture(root, complete_matrix=False)
            with self.assertRaises(ValueError): parser.repair_matrix(root)
            self.assertFalse(json.loads((root / "matrix-result.json").read_text())["Complete"])


@unittest.skipUnless(shutil.which("g++"), "g++ unavailable")
class NativeScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.temp.name) / "scope-test"
        subprocess.run(["g++", "-std=c++17", "-I" + str(ROOT / "ggml/include"),
                        str(ROOT / "tools/evox2/tests/test_mtp_diag.cpp"), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_mode(self, mode, argument=""):
        return subprocess.run([str(self.binary), argument], env={**os.environ, "LLAMA_MTP_DIAG": mode},
                              capture_output=True, text=True, check=True)

    def test_off_avoids_logging_and_clock_calls(self):
        self.assertEqual(self.run_mode("off", "off").stdout, "")

    def test_wall_and_sync_produce_parseable_nested_records(self):
        for mode in ("wall", "sync"):
            r = parser.summarize(self.run_mode(mode).stdout.splitlines())
            self.assertTrue(r["Complete"], r["Issues"])
            self.assertEqual(r["Modes"], [mode])
            self.assertEqual(r["Groups"][0]["CounterSums"]["copied_cells"], 256000)

    def test_exception_marks_scope_incomplete(self):
        self.run_mode("wall", "throw")


if __name__ == "__main__":
    unittest.main()
