import importlib.util
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
