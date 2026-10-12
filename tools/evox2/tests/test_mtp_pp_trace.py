#!/usr/bin/env python3
"""Standard-library regression tests for summarize_mtp_pp_trace.py."""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "benchmark" / "summarize_mtp_pp_trace.py"
spec = importlib.util.spec_from_file_location("summarize_mtp_pp_trace", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

BASE = {
    "total_us": 1200, "target_us": 0, "target_sync_us": 0,
    "spec_us": 0, "hidden_get_us": 200, "prepare_us": 100,
    "draft_us": 750, "verify_copy_us": 100,
}


def line(record_type: str, *, calls: int = 1, tokens: int = 1024,
         row: bool = False, **override) -> str:
    attrs = dict(BASE, **override)
    fixed = (f"mtp_pp_trace_v1 type={record_type} role=draft phase=prompt "
             + ("end_pos=65535 n_tokens=1024 " if row else
                f"kv_bin=0-32768 calls={calls} tokens={tokens} "))
    # Caller can supply a separate bin and numeric values when needed.
    return fixed + " ".join(f"{key}={value}" for key, value in attrs.items())


class TestMtpPpTrace(unittest.TestCase):
    def test_bins_only(self):
        b, rows = module.parse_lines([line("bin")])
        self.assertEqual((len(b), len(rows)), (1, 0))
        module.validate(b, rows)

    def test_detail_and_bin_consistency(self):
        b, rows = module.parse_lines([
            line("bin").replace("kv_bin=0-32768", "kv_bin=32769-65536"),
            line("row", row=True),
        ])
        module.validate(b, rows)
        self.assertEqual(rows[0]["draft_us_per_token"], round(750 / 1024, 3))
        self.assertEqual(rows[0]["kv_bin"], "32769-65536")

    def test_missing_row_or_invalid_time_is_rejected(self):
        b, rows = module.parse_lines([
            line("bin").replace("kv_bin=0-32768", "kv_bin=32769-65536").replace("calls=1", "calls=2"),
            line("row", row=True),
        ])
        with self.assertRaisesRegex(ValueError, "incomplete detail"):
            module.validate(b, rows)
        with self.assertRaisesRegex(ValueError, "negative"):
            module.parse_lines([line("row", row=True, draft_us=-1)])

    def test_prefixed_log_line_and_duplicate_detection(self):
        b, rows = module.parse_lines(["server timestamp foo: " + line("bin")])
        self.assertEqual(len(b), 1)
        self.assertEqual(rows, [])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            module.parse_lines([line("bin") + " total_us=30"])

    def test_end_to_end_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            log = root / "stderr.log"
            log.write_text(
                line("bin").replace("kv_bin=0-32768", "kv_bin=32769-65536") + "\n"
                + line("row", row=True) + "\n", encoding="utf-8")
            result = module.main(["--log", str(log), "--outdir", str(root / "out"),
                                  "--require-prompt-draft", "--require-detail"])
            self.assertEqual(result, 0)
            self.assertTrue((root / "out" / "mtp-pp-rows.csv").is_file())
            self.assertTrue((root / "out" / "mtp-pp-bins.csv").is_file())
            self.assertTrue((root / "out" / "mtp-pp-summary.json").is_file())


if __name__ == "__main__":
    unittest.main()
