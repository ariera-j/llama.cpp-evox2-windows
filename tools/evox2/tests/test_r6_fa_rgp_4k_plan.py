"""Static safety check for dedicated short 4k RGP/FA capture plan.

Not a C++ build or a GPU capture test.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
PLAN_PATH = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-gate1-4k-20261106.psd1"


class R6FaRgp4kPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = PLAN_PATH.read_text(encoding="utf-8")

    def test_4k_context_microbatch_and_no_generation(self):
        for literal in (
            "PromptTokens     = @(4096)",
            "Context          = 8192",
            "UBatch           = 1024",
            "Batch            = 2048",
            "GenerationTokens = @(0)",
            "NoWarmup         = $true",
            "PromptSlice      = 'head'",
            "GpuLayers        = 999",
            "FlashAttn        = 'auto'",
        ):
            self.assertIn(literal, self.plan)
        self.assertNotIn("65536", self.plan)

    def test_distinct_variants_and_marker_only_capture(self):
        self.assertIn("Name = 'hosttrace-4k'", self.plan)
        self.assertIn("Name = 'rgp-markers-4k'", self.plan)
        self.assertEqual(self.plan.count("GGML_VK_FA_RGP_MARKERS = '1'"), 2)
        self.assertEqual(self.plan.count("GGML_VK_FA_DISPATCH_TRACE = '1'"), 1)
        self.assertIn("GGML_VK_FA_DISPATCH_TRACE = $null", self.plan)
        self.assertIn("GGML_VK_FA_DISPATCH_TRACE         = $null", self.plan)
        self.assertIn("GGML_VK_QSA_UNION                 = '0'", self.plan)
        self.assertIn("GGML_VK_PERF_LOGGER               = $null", self.plan)
        self.assertIn("GGML_VK_DEBUG_MARKERS             = $null", self.plan)

    def test_reuse_validated_binary_and_model(self):
        self.assertIn("R6PpFaRgpVulkan", self.plan)
        self.assertIn("UnslothPle16", self.plan)
        self.assertIn("vulkan-fa-rgp-4k", self.plan)
        self.assertNotIn("CombinedVulkan", self.plan)
        self.assertIn("ResourceMonitor  = $true", self.plan)
        self.assertIn("Repetitions      = 1", self.plan)


if __name__ == "__main__":
    unittest.main()
