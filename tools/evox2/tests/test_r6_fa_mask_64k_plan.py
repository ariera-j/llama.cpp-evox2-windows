"""Static verification for 64k Vulkan FA mask capture plan."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-fa-mask-tile-gate2-64k-20261106.psd1"

class Gate2Mask64kTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = PLAN.read_text(encoding="utf-8")

    def test_fixed_parameters(self):
        for value in ("PromptTokens     = @(61777)", "GenerationTokens = @(0)",
                      "Context          = 65536", "UBatch           = 1024",
                      "NoWarmup         = $true", "PromptSlice      = 'head'",
                      "GGML_VK_QSA_UNION                 = '0'",
                      "GGML_VK_FA_RGP_MARKERS            = $null",
                      "GGML_VK_FA_DISPATCH_TRACE         = $null"):
            self.assertIn(value, self.text)

    def test_distinct_output_and_inputs(self):
        self.assertEqual(self.text.count("Tool = 'bench'"), 2)
        self.assertEqual(self.text.count("GGML_VK_FA_MASK_DIAG       = '1'"), 2)
        self.assertEqual(self.text.count("GGML_VK_FA_MASK_DIAG_KV    = '49152'"), 2)
        self.assertEqual(self.text.count("GGML_VK_FA_MASK_DIAG_QUERY = 'Qcur-19'"), 2)
        for term in ("mask-literature-64k", "mask-code-64k",
                     "literature-49152", "code-49152",
                     "wagahaiwa_nekodearu_utf8.txt", "llamacpp-inference-code.txt"):
            self.assertIn(term, self.text)
        self.assertEqual(self.text.count("GGML_VK_FA_MASK_DIAG_FILE  = "), 2)

if __name__ == "__main__":
    unittest.main()
