"""Regression tests for the rollback C/A/B trace validator (no GPU needed)."""
from __future__ import annotations

import json
import tempfile
import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "benchmark"))
from analyze_mtp_rollback import _summary, inspect


def events(text: str):
    from analyze_mtp_rollback import _events
    return _events(text)


def make_run(folder: Path, arm: str, *, scenario: str, stdout="same", restore=True, sha="valid"):
    folder.mkdir(parents=True)
    expected = {"C": ("0", "0"), "A": ("1", "0"), "B": ("1", "1")}
    sb, flat = expected[arm]
    forced = scenario != "natural"
    synth = {"reject-zero": "0,0", "reject-after-one": "1,0", "accept-all": "1,1"}.get(scenario)
    args = ["-n", "128"]
    if synth:
        args += ["--spec-synth-rates", synth]
    condition = {
        "Arguments": args,
        "Environment": {
            "LLAMA_MTP_ROLLBACK_DIAG": "1",
            "LLAMA_MTP_ROLLBACK_TAG": arm,
            "LLAMA_MTP_DRAFT_PREFILL_KV_CROP": sb,
            "LLAMA_MTP_EH_PROJ_FLATTEN": flat,
            "LLAMA_MTP_ROLLBACK_FORCE_CKPT": "1" if forced else "0",
        },
        "ModelIdentity": {"Name": "a.gguf"},
        "DraftModelIdentity": {"Name": "d.gguf"},
        "InputIdentity": {"Sha256": "aabb"},
    }
    result = {
        "Status": "OK", "ExitCode": 0, "RunId": f"run-{arm}",
        "ExecutableSha256": sha, "RuntimeArtifactDigest": "runtime",
        "PromptTokens": 163, "GeneratedTokens": 128,
        "DraftAccepted": 10, "DraftGenerated": 50,
    }
    first = 0 if scenario == "reject-zero" else 1
    if scenario == "accept-all":
        body = ("event=draft round=1 size=2\n"
                "event=decision round=1 drafted=2 accepted=2 rollback=0 replay=0\n"
                "event=commit round=1 accepted=2 replay=0\n")
    elif scenario == "natural":
        body = ("event=draft round=1 size=2\n"
                "event=decision round=1 drafted=2 accepted=1 rollback=1 replay=0\n"
                "event=commit round=1 accepted=1 replay=0\n")
    else:
        body = (f"event=draft round=1 size=2\n"
                f"event=decision round=1 drafted=2 accepted={first} rollback={2 - first} replay=0\n")
        if restore:
            body += ("event=checkpoint_restore round=1\n"
                     "event=decision round=1 drafted=1 accepted=1 rollback=0 replay=1\n"
                     "event=commit round=1 accepted=0 replay=1\n")
    stderr = "mtp_rollback_diag_v1 event=init tag=" + arm + "\n"
    stderr += "".join("mtp_rollback_diag_v1 " + line + " tag=" + arm + "\n" for line in body.strip().splitlines())

    (folder / "conditions.json").write_text(json.dumps(condition), encoding="utf-8")
    (folder / "result.json").write_text(json.dumps(result), encoding="utf-8")
    (folder / "stderr.log").write_text(stderr, encoding="utf-8")
    (folder / "stdout.log").write_text(stdout + "\n[ Prompt: 40.1 t/s | Generation: 22.3 t/s ]", encoding="utf-8")


class TestRollbackAnalysis(unittest.TestCase):
    def test_synthetic_rejection_and_acceptance(self):
        for scenario in ("reject-zero", "reject-after-one", "accept-all", "natural"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as td:
                path = Path(td)
                for arm in "CAB":
                    make_run(path / ("run-" + arm), arm, scenario=scenario)
                report = inspect(path, scenario)
                self.assertEqual(report["status"], "PASS", report["problems"])

    def test_missing_replay_fails(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td)
            for arm in "CAB":
                make_run(path / ("run-" + arm), arm, scenario="reject-zero", restore=(arm != "B"))
            report = inspect(path, "reject-zero")
            self.assertEqual(report["status"], "FAIL")
            self.assertTrue(any("B" in p for p in report["problems"]))

    def test_output_drift_fails(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td)
            for arm in "CAB":
                make_run(path / ("run-" + arm), arm, scenario="reject-after-one",
                         stdout="different" if arm == "B" else "same")
            report = inspect(path, "reject-after-one")
            self.assertEqual(report["status"], "FAIL")
            self.assertTrue(any("stdout" in p for p in report["problems"]))


if __name__ == "__main__":
    unittest.main()
