#!/usr/bin/env python3
"""Offline mock unit tests for review/hip2e4/run_hip2e4_suite.py (no SSH/GPU)."""

import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_hip2e4_suite as suite


def make_audit_json(**overrides) -> dict:
    base = {
        "Head": suite.PINNED["source_commit"],
        "RemoteMain": suite.PINNED["main_sha"],
        "RemoteBranch": suite.PINNED["source_commit"],
        "Clean": True,
        "Hashes": dict(suite.EXPECTED_HASH_MAP),
        "LibompSystem32": suite.PINNED["libomp_sha256"],
        "PMode": "Performance",
        "BootUtc": "2026-11-28T02:39:40.0575102Z",
        "SysId": 70257,
        "AppId": 44878,
        "PhysAvailGiB": 25.5,
        "CommitGiB": 8.3,
        "CommitLimitGiB": 127.6,
        "DedicatedGiB": 0.42,
        "SharedGiB": 0.065,
    }
    base.update(overrides)
    return base


def make_sched_stderr(case_id: str) -> str:
    e = suite.SCHED_EXPECTED[case_id]
    return case_id + " " + " ".join(f"{key}={value}" for key, value in e.items()) + "\n"


def make_case_report(case_id: str, run_id: str = "hip2e4-test-run", **overrides) -> dict:
    stdout = f"{case_id} OP ...\n"
    stderr = ""
    if case_id in suite.SCHED_CASES:
        stdout += "max relative error 2.115e-06 max condition 566.14\n"
        stderr += make_sched_stderr(case_id)
    if case_id == suite.PLACEMENT_CASE:
        stderr = make_sched_stderr(case_id)
        stdout += f"PASS {case_id} allocation-only\n"
    else:
        stdout += f"PASS {case_id} reference SHA256 {suite.EXPECTED_REF_SHA256[case_id]}\n"

    rep = {
        "CaseId": case_id,
        "Pid": 1234,
        "ProcessStartUtc": "2026-11-28T15:00:00Z",
        "StartUtc": "2026-11-28T15:00:00Z",
        "EndUtc": "2026-11-28T15:00:00.3Z",
        "ElapsedSeconds": 0.3,
        "TimedOut": False,
        "Unconfirmed": False,
        "ExitCode": 0,
        "MonitorError": None,
        "Command": f"python -I -B fixtures.py gpu --case {case_id}",
        "Pre": {
            "Mem": {"PhysAvailGiB": 25.5, "CommitGiB": 8.3, "CommitLimGiB": 127.6},
            "Wddm": {"DedicatedGiB": 0.42, "SharedGiB": 0.065},
            "PMode": "Performance",
            "BootUtc": "2026-11-28T02:39:40.0575102Z",
            "SysId": 70257,
            "AppId": 44878,
        },
        "DuringSamples": [],
        "DuringSampleErrors": [],
        "DuringPeakNote": "unmeasured (duration < 2s)",
        "Post": {
            "Mem": {"PhysAvailGiB": 25.4, "CommitGiB": 8.35, "CommitLimGiB": 127.6},
            "Wddm": {"DedicatedGiB": 0.42, "SharedGiB": 0.065},
            "PMode": "Performance",
            "BootUtc": "2026-11-28T02:39:40.0575102Z",
            "SysId": 70257,
            "AppId": 44878,
            "CommitDeltaGiB": 0.05,
            "DedicatedDeltaGiB": 0.0,
            "ResidualCount": 0,
            "SysErrors": [],
            "AppErrors": [],
        },
        "Stdout": stdout,
        "Stderr": stderr,
        "LogStem": suite.expected_log_stem(run_id, case_id),
    }
    for k, v in overrides.items():
        if k == "Post" and isinstance(v, dict):
            rep["Post"].update(v)
        elif k == "Pre" and isinstance(v, dict):
            rep["Pre"].update(v)
        else:
            rep[k] = v
    return rep


class RunHip2eSuiteTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.dict(suite.PINNED, source_commit="a" * 40, binary_dir="mock"))
        self.enterContext(patch.dict(suite.EXPECTED_HASH_MAP,
                                     {k: "B" * 64 for k in suite.EXPECTED_HASH_MAP}))

    def test_unpinned_refuses_before_transport(self):
        with patch.dict(suite.PINNED, source_commit=""), tempfile.TemporaryDirectory() as td:
            with self.assertRaisesRegex(ValueError, "pins are incomplete"):
                suite.run_suite(Path(td), ssh_runner=lambda *args: self.fail("SSH called"))

    def test_copy_layout_diagnostics(self):
        for cid in ("S-HC-PIN-COPY", "S-ID-PIN-COPY"):
            fields = make_sched_stderr(cid).split()
            for key in ("split_copy", "id_copy", "observed_span", "observed_pitch"):
                field = next(f for f in fields if f.startswith(key + "="))
                for bad in ("", key + "=999"):
                    with self.subTest(cid=cid, key=key, bad=bad):
                        rep = make_case_report(cid, Stderr=" ".join(fields).replace(field, bad))
                        result = suite.evaluate_case_result(cid, suite.CommandResult(
                            0, "REPORT_JSON=" + json.dumps(rep), ""), make_audit_json(),
                            run_id="hip2e4-test-run")
                        self.assertEqual(result["status"], "FAIL")
                        self.assertIn("scheduler route mismatch", result["reason"])

    def test_placement_evidence(self):
        cid = suite.PLACEMENT_CASE
        original = make_sched_stderr(cid)
        for key in suite.SCHED_EXPECTED[cid]:
            with self.subTest(key=key):
                rep = make_case_report(cid, Stderr=original.replace(key + "=", key + "=9"))
                result = suite.evaluate_case_result(cid, suite.CommandResult(
                    0, "REPORT_JSON=" + json.dumps(rep), ""), make_audit_json(), run_id="hip2e4-test-run")
                self.assertEqual(result["status"], "FAIL")
        rep = make_case_report(cid, Stdout=f"PASS {cid} reference SHA256 fake")
        result = suite.evaluate_case_result(cid, suite.CommandResult(
            0, "REPORT_JSON=" + json.dumps(rep), ""), make_audit_json(), run_id="hip2e4-test-run")
        self.assertIn("allocation-only PASS", result["reason"])

    def test_stdin_transport_command_is_short_and_no_reserved_input_var(self) -> None:
        remote_cmd = suite.build_remote_ssh_command()
        self.assertLess(len(remote_cmd), 600)
        scripts = [
            suite.build_pre_audit_ps(),
            suite.build_case_ps("1", "hip2e4-run1", 70257, 44878, make_audit_json()),
        ]
        for sc in scripts:
            self.assertIsNone(re.search(r"(?i)\$input\b", sc))

    def test_invalid_case_id_rejected(self) -> None:
        base = make_audit_json()
        for bad in ["", "1; whoami", "99", "S-UNKNOWN", "$(calc)"]:
            with self.assertRaises(ValueError):
                suite.validate_case_id(bad)
            with self.assertRaises(ValueError):
                suite.build_case_ps(bad, "hip2e4-run1", 70257, 44878, base)
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(ValueError):
                suite.run_suite(Path(td), cases=["1", "BAD_ID"])

    def test_all_14_cases_pass_in_exact_order_and_collect_56_logs(self) -> None:
        calls = []

        def mock_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            if "AUDIT_JSON=" in ps_script:
                calls.append("AUDIT")
                return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")
            cid = re.search(r"\$caseId = '([^']+)'", ps_script).group(1)
            calls.append(cid)
            return suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report(cid, run_id="hip2e4-test-run")), "")

        def mock_scp(remote_glob: str, local_dir: Path, timeout: int) -> suite.CommandResult:
            local_dir.mkdir(parents=True, exist_ok=True)
            for cid in suite.CASES:
                prefix = f"hip2e4-test-run-{suite.safe_case_name(cid)}"
                rep = make_case_report(cid, run_id="hip2e4-test-run")
                (local_dir / f"{prefix}.stdout.log").write_text(rep["Stdout"], encoding="utf-8")
                (local_dir / f"{prefix}.stderr.log").write_text(rep["Stderr"], encoding="utf-8")
                (local_dir / f"{prefix}.report.json").write_text(json.dumps(rep), encoding="utf-8")
                (local_dir / f"{prefix}.state.json").write_text(
                    json.dumps({
                        "CaseId": cid, "Pid": 1234, "ProcessStartUtc": "2026-11-28T15:00:00Z",
                        "Status": "Completed", "ExitCode": 0, "TimedOut": False, "Unconfirmed": False,
                        "LogStem": rep["LogStem"],
                    }),
                    encoding="utf-8",
                )
            return suite.CommandResult(0, "", "")

        with tempfile.TemporaryDirectory() as td:
            res = suite.run_suite(Path(td), run_id="hip2e4-test-run", ssh_runner=mock_ssh, scp_runner=mock_scp)
            self.assertEqual(res["overall_status"], "PASS")
            self.assertTrue(res["gpu_cases_passed"])
            self.assertEqual(calls, ["AUDIT", *suite.CASES])
            self.assertEqual([c["status"] for c in res["cases"]], ["PASS"] * 14)
            self.assertEqual(res["collected_logs"]["collected_count"], 56)
            sums = (Path(td) / "hip2e4-test-run-logs" / "SHA256SUMS").read_text(encoding="utf-8")
            self.assertEqual(len(sums.strip().splitlines()), 56)
            # Verify scheduler route diagnostics saved
            s_hc_cpu = [c for c in res["cases"] if c["case_id"] == "S-HC-CPU"][0]
            self.assertEqual(s_hc_cpu["scheduler_route"]["split_copy"], 1)
            self.assertEqual(s_hc_cpu["scheduler_route"]["sgemms"], 1)

    def test_pre_audit_only_mode_never_launches_gpu_cases(self) -> None:
        calls = []

        def mock_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            calls.append("AUDIT" if "AUDIT_JSON=" in ps_script else "CASE")
            return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")

        with tempfile.TemporaryDirectory() as td:
            res = suite.run_suite(Path(td), run_id="hip2e4-r-pre-only", ssh_runner=mock_ssh, pre_audit_only=True)
            self.assertEqual(res["overall_status"], "PASS")
            self.assertTrue(res["pre_audit_only"])
            self.assertEqual(calls, ["AUDIT"])
            self.assertTrue(all(c["status"] == "NOT RUN" for c in res["cases"]))

    def test_pre_audit_hash_and_invalid_values_blocked(self) -> None:
        # Empty Hashes dict must be rejected
        with self.assertRaises(ValueError):
            suite.validate_pre_audit_json(make_audit_json(Hashes={}))
        # Bad hip_dll hash must be rejected
        bad_hashes = dict(suite.EXPECTED_HASH_MAP)
        bad_hashes["hip_dll"] = "0" * 64
        with self.assertRaises(ValueError):
            suite.validate_pre_audit_json(make_audit_json(Hashes=bad_hashes))
        # Bad libomp hash must be rejected
        with self.assertRaises(ValueError):
            suite.validate_pre_audit_json(make_audit_json(LibompSystem32="0" * 64))
        # Missing BootUtc, NaN, bool, low memory, negative dedicated, commit > limit, dirty, wrong PMode
        bad_audit = make_audit_json()
        del bad_audit["BootUtc"]
        with self.assertRaises(ValueError):
            suite.validate_pre_audit_json(bad_audit)

        for bad_kwargs in [
            {"PhysAvailGiB": float("nan")},
            {"PhysAvailGiB": True},
            {"PhysAvailGiB": 15.9},
            {"DedicatedGiB": -0.1},
            {"CommitGiB": 130.0},
            {"Clean": False},
            {"PMode": "Balanced"},
        ]:
            with self.assertRaises(ValueError):
                suite.validate_pre_audit_json(make_audit_json(**bad_kwargs))

    def test_case_report_strict_schema_and_monotonic_checks(self) -> None:
        baseline = make_audit_json()

        # ChatGPT repro 1: CaseId changed to 9 and fields deleted
        rep = make_case_report("1")
        rep["CaseId"] = "9"
        for k in ("TimedOut", "Unconfirmed"):
            del rep[k]
        for k in ("SysErrors", "AppErrors"):
            del rep["Post"][k]
        ev = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev["status"], "FAIL")

        # Missing MonitorError or DuringSampleErrors must be rejected
        for missing_key in ("MonitorError", "DuringSampleErrors"):
            rep_m = make_case_report("1")
            del rep_m[missing_key]
            ev_m = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_m), ""), baseline, run_id="hip2e4-test-run")
            self.assertEqual(ev_m["status"], "FAIL")
            self.assertIn("missing required fields", ev_m["reason"])

        # Pre.Mem.PhysAvailGiB == 1 must be rejected
        rep_p = make_case_report("1", Pre={"Mem": {"PhysAvailGiB": 1.0, "CommitGiB": 8.3, "CommitLimGiB": 127.6}})
        ev_p = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_p), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev_p["status"], "FAIL")
        self.assertIn("Pre PhysAvailGiB", ev_p["reason"])

        # Post.SysId / AppId < Pre must be rejected
        rep_s = make_case_report("1", Post={"SysId": 70256})
        ev_s = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_s), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev_s["status"], "FAIL")
        self.assertIn("regressed", ev_s["reason"])

        # Invalid LogStem must be rejected
        rep_l = make_case_report("1", LogStem=r"C:\wrong\path")
        ev_l = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_l), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev_l["status"], "FAIL")
        self.assertIn("LogStem mismatch", ev_l["reason"])

        # CommitDeltaGiB recompute mismatch must be rejected
        rep_d = make_case_report("1", Post={"CommitDeltaGiB": 0.5})
        ev_d = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_d), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev_d["status"], "FAIL")
        self.assertIn("CommitDeltaGiB mismatch", ev_d["reason"])

        # ElapsedSeconds >= 60 even when TimedOut=False must be rejected
        rep_e = make_case_report("1", ElapsedSeconds=61.0, TimedOut=False)
        ev_e = suite.evaluate_case_result("1", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep_e), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev_e["status"], "FAIL")
        self.assertIn("elapsed seconds >= 60.0", ev_e["reason"])

    def test_scheduler_route_and_diagnostic_checks(self) -> None:
        baseline = make_audit_json()
        # Missing stderr route line
        rep = make_case_report("S-HC-CPU", Stderr="")
        ev = suite.evaluate_case_result("S-HC-CPU", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev["status"], "FAIL")
        self.assertIn("missing scheduler route diagnostic", ev["reason"])

        # Mismatched route field (split_copy=0 instead of 1)
        bad_stderr = make_sched_stderr("S-HC-CPU").replace("split_copy=1", "split_copy=0")
        rep2 = make_case_report("S-HC-CPU", Stderr=bad_stderr)
        ev2 = suite.evaluate_case_result("S-HC-CPU", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep2), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev2["status"], "FAIL")
        self.assertIn("scheduler route mismatch", ev2["reason"])

        # Missing stdout error diagnostic
        rep3 = make_case_report("S-HC-PIN-COPY", Stdout=f"S-HC-PIN-COPY MM ...\nPASS S-HC-PIN-COPY reference SHA256 {suite.EXPECTED_REF_SHA256['S-HC-PIN-COPY']}\n")
        ev3 = suite.evaluate_case_result("S-HC-PIN-COPY", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep3), ""), baseline, run_id="hip2e4-test-run")
        self.assertEqual(ev3["status"], "FAIL")
        self.assertIn("missing scheduler error diagnostic", ev3["reason"])

    def test_ssh_timeout_expired_saves_summary_and_stops(self) -> None:
        calls = []

        def mock_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            if "AUDIT_JSON=" in ps_script:
                calls.append("AUDIT")
                return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")
            cid = re.search(r"\$caseId = '([^']+)'", ps_script).group(1)
            calls.append(cid)
            if cid == "2":
                raise subprocess.TimeoutExpired(cmd="ssh", timeout=timeout)
            return suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report(cid, run_id="hip2e4-r-ssh-to")), "")

        with tempfile.TemporaryDirectory() as td:
            res = suite.run_suite(Path(td), run_id="hip2e4-r-ssh-to", ssh_runner=mock_ssh, collect_on_pass=False)
            self.assertEqual(res["overall_status"], "FAIL")
            self.assertIn("TimeoutExpired", res["stop_reason"])
            self.assertEqual(calls, ["AUDIT", "1", "1-NC", "2"])
            saved = json.loads((Path(td) / "hip2e4-r-ssh-to-summary.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["overall_status"], "FAIL")
            self.assertEqual(saved["cases"][3]["status"], "NOT RUN")

    def test_log_collection_content_and_overwrite_guards(self) -> None:
        def mock_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            if "AUDIT_JSON=" in ps_script:
                return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")
            cid = re.search(r"\$caseId = '([^']+)'", ps_script).group(1)
            return suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report(cid, run_id="hip2e4-r-bad-log")), "")

        # Content mismatch between stdout.log and report.json
        def mismatch_scp(remote_glob: str, local_dir: Path, timeout: int) -> suite.CommandResult:
            local_dir.mkdir(parents=True, exist_ok=True)
            for cid in suite.CASES:
                prefix = f"hip2e4-r-bad-log-{suite.safe_case_name(cid)}"
                rep = make_case_report(cid, run_id="hip2e4-r-bad-log")
                (local_dir / f"{prefix}.stdout.log").write_text("TAMPERED" if cid == "1" else rep["Stdout"], encoding="utf-8")
                (local_dir / f"{prefix}.stderr.log").write_text(rep["Stderr"], encoding="utf-8")
                (local_dir / f"{prefix}.report.json").write_text(json.dumps(rep), encoding="utf-8")
                (local_dir / f"{prefix}.state.json").write_text(
                    json.dumps({
                        "CaseId": cid, "Pid": 1234, "ProcessStartUtc": "2026-11-28T15:00:00Z",
                        "Status": "Completed", "ExitCode": 0, "TimedOut": False, "Unconfirmed": False,
                        "LogStem": rep["LogStem"],
                    }),
                    encoding="utf-8",
                )
            return suite.CommandResult(0, "", "")

        with tempfile.TemporaryDirectory() as td:
            res = suite.run_suite(Path(td), run_id="hip2e4-r-bad-log", ssh_runner=mock_ssh, scp_runner=mismatch_scp)
            self.assertEqual(res["overall_status"], "FAIL")
            self.assertTrue(res["gpu_cases_passed"])
            self.assertIn("content differs from report.json", res["stop_reason"])

            with self.assertRaises(FileExistsError):
                suite.run_suite(Path(td), run_id="hip2e4-r-bad-log", ssh_runner=mock_ssh, scp_runner=mismatch_scp)

        # CRLF preservation: matching CRLF logs must PASS, LF-only file vs CRLF report must FAIL, invalid UTF-8 must FAIL
        def crlf_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            if "AUDIT_JSON=" in ps_script:
                return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")
            cid = re.search(r"\$caseId = '([^']+)'", ps_script).group(1)
            rep = make_case_report(cid, run_id="hip2e4-r-crlf")
            rep["Stdout"] = rep["Stdout"].replace("\n", "\r\n")
            rep["Stderr"] = rep["Stderr"].replace("\n", "\r\n")
            return suite.CommandResult(0, "REPORT_JSON=" + json.dumps(rep), "")

        def crlf_scp(remote_glob: str, local_dir: Path, timeout: int) -> suite.CommandResult:
            local_dir.mkdir(parents=True, exist_ok=True)
            for cid in suite.CASES:
                prefix = f"hip2e4-r-crlf-{suite.safe_case_name(cid)}"
                rep = make_case_report(cid, run_id="hip2e4-r-crlf")
                rep["Stdout"] = rep["Stdout"].replace("\n", "\r\n")
                rep["Stderr"] = rep["Stderr"].replace("\n", "\r\n")
                (local_dir / f"{prefix}.stdout.log").write_bytes(rep["Stdout"].encode("utf-8"))
                (local_dir / f"{prefix}.stderr.log").write_bytes(rep["Stderr"].encode("utf-8"))
                (local_dir / f"{prefix}.report.json").write_text(json.dumps(rep), encoding="utf-8")
                (local_dir / f"{prefix}.state.json").write_text(
                    json.dumps({
                        "CaseId": cid, "Pid": 1234, "ProcessStartUtc": "2026-11-28T15:00:00Z",
                        "Status": "Completed", "ExitCode": 0, "TimedOut": False, "Unconfirmed": False,
                        "LogStem": rep["LogStem"],
                    }),
                    encoding="utf-8",
                )
            return suite.CommandResult(0, "", "")

        with tempfile.TemporaryDirectory() as td:
            res_ok = suite.run_suite(Path(td), run_id="hip2e4-r-crlf", ssh_runner=crlf_ssh, scp_runner=crlf_scp)
            self.assertEqual(res_ok["overall_status"], "PASS")
            self.assertEqual(res_ok["collected_logs"]["collected_count"], 56)

        def invalid_utf8_scp(remote_glob: str, local_dir: Path, timeout: int) -> suite.CommandResult:
            crlf_scp(remote_glob, local_dir, timeout)
            (local_dir / "hip2e4-r-crlf-1.stdout.log").write_bytes(b"\xff\xfe\x00")
            return suite.CommandResult(0, "", "")

        with tempfile.TemporaryDirectory() as td:
            res_bad_utf8 = suite.run_suite(Path(td), run_id="hip2e4-r-crlf", ssh_runner=crlf_ssh, scp_runner=invalid_utf8_scp)
            self.assertEqual(res_bad_utf8["overall_status"], "FAIL")
            self.assertIn("log collection failed", res_bad_utf8["stop_reason"])

    def _run_stop_at_case(self, target_case: str, mock_result: suite.CommandResult, expected_substr: str) -> None:
        calls = []

        def mock_ssh(ps_script: str, remote_cmd: str, timeout: int) -> suite.CommandResult:
            if "AUDIT_JSON=" in ps_script:
                calls.append("AUDIT")
                return suite.CommandResult(0, "AUDIT_JSON=" + json.dumps(make_audit_json()), "")
            cid = re.search(r"\$caseId = '([^']+)'", ps_script).group(1)
            calls.append(cid)
            if cid == target_case:
                return mock_result
            return suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report(cid, run_id="hip2e4-r-stop")), "")

        with tempfile.TemporaryDirectory() as td:
            res = suite.run_suite(Path(td), run_id="hip2e4-r-stop", ssh_runner=mock_ssh, collect_on_pass=False)
            self.assertEqual(res["overall_status"], "FAIL")
            self.assertIn(expected_substr, res["stop_reason"])
            idx = suite.CASES.index(target_case)
            self.assertEqual(calls, ["AUDIT", *suite.CASES[: idx + 1]])

    def test_failure_modes_stop_and_preserve_not_run(self) -> None:
        self._run_stop_at_case("2", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("2", run_id="hip2e4-r-stop", ExitCode=3)), ""), "process exit code 3")
        self._run_stop_at_case("5", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("5", run_id="hip2e4-r-stop", TimedOut=True, ExitCode=-1)), ""), "timeout")
        self._run_stop_at_case("6", suite.CommandResult(255, "", "Connection closed"), "SSH exited with code 255")
        self._run_stop_at_case("1-NC", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("1-NC", run_id="hip2e4-r-stop", Stdout="1-NC F32_NC ...\n")), ""), "missing or mismatched PASS SHA256")
        self._run_stop_at_case("8", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("8", run_id="hip2e4-r-stop", Post={"CommitDeltaGiB": 4.5, "Mem": {"PhysAvailGiB": 25.0, "CommitGiB": 12.8, "CommitLimGiB": 127.6}})), ""), "CommitDeltaGiB")
        self._run_stop_at_case("9", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("9", run_id="hip2e4-r-stop", Post={"CommitDeltaGiB": 4.3, "Mem": {"PhysAvailGiB": 20.0, "CommitGiB": 12.6, "CommitLimGiB": 127.6}})), ""), "CommitDeltaGiB")
        self._run_stop_at_case("2-C", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("2-C", run_id="hip2e4-r-stop", Post={"Mem": {"PhysAvailGiB": 15.9, "CommitGiB": 8.4, "CommitLimGiB": 127.6}})), ""), "PhysAvailGiB")
        self._run_stop_at_case("S-HC-CPU", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("S-HC-CPU", run_id="hip2e4-r-stop", Post={"PMode": "Balanced"})), ""), "P-MODE")
        self._run_stop_at_case("S-HC-PIN-COPY", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("S-HC-PIN-COPY", run_id="hip2e4-r-stop", Post={"SysErrors": [{"Id": 4101}]})), ""), "System error events")
        self._run_stop_at_case("S-ID-PIN-COPY", suite.CommandResult(0, "REPORT_JSON=" + json.dumps(make_case_report("S-ID-PIN-COPY", run_id="hip2e4-r-stop", Unconfirmed=True)), ""), "unconfirmed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
