"""Static opt-in contract for the r6 ROCm RGP SSE capture cue.

These tests do not replace a native Windows ROCm build or an RGP trace.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "tools" / "cli" / "cli-context.cpp"
PLAN = ROOT / "tools" / "evox2" / "benchmark" / "configs" / "qwen38-r6-rocm-qsa-rgp-128k-20261102.psd1"


class TestRocmRgpCue(unittest.TestCase):
    def test_explicit_opt_in_and_host_only(self):
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn('std::getenv("LLAMA_EVOX2_RGP_SSE_TRACE")', text)
        self.assertIn('std::string(rgp_env) == "1"', text)
        self.assertIn('if (!rgp_trace)', text)
        self.assertIn('rgp_event("first_text_delta")', text)
        self.assertIn('rgp_event("text_progress")', text)
        self.assertIn('rgp_event(err.empty() && !stream_error ? "stream_end" : "stream_error")', text)
        self.assertIn('std::fflush(stderr);', text)

    def test_bounded_profile_plan(self):
        text = PLAN.read_text(encoding="utf-8")
        self.assertIn("R6RocmQsaRgp", text)
        self.assertIn("InputKey = '128k'", text)
        self.assertIn("Context = 131072", text)
        self.assertIn("Mtp              = $false", text)
        self.assertIn("LLAMA_EVOX2_RGP_SSE_TRACE       = '1'", text)
        self.assertIn("QWEN4EXP_QSA_GATHER              = '0'", text)
        self.assertIn("ResourceMonitor  = $false", text)


if __name__ == "__main__":
    unittest.main()
