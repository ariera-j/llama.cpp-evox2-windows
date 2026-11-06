"""Check that the Gate2 source remains opt-in and the smoke plan is short."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
TYPES = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan-types.h"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-fa-mask-tile-gate2-smoke-20261106.psd1"


class Gate2SnapshotContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.types = TYPES.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")

    def test_opt_in_and_target(self):
        self.assertIn('std::getenv("GGML_VK_FA_MASK_DIAG")', self.cpp)
        self.assertIn('std::strcmp(env, "1") == 0', self.cpp)
        self.assertIn("ggml_vk_fa_mask_diag_target_kv()", self.cpp)
        self.assertIn("ggml_vk_fa_mask_diag_target_query()", self.cpp)

    def test_private_bounded_copy_and_deferred_read(self):
        fa = self.cpp.split("void ggml_vk_flash_attn(", 1)[1].split(
            "static vk_conv_shapes ggml_vk_conv_select_shape(", 1
        )[0]
        self.assertIn("bytes <= (1u << 20)", fa)
        self.assertIn("!ctx->fa_mask_diag_captured", fa)
        self.assertIn("ggml_vk_create_buffer_device", fa)
        self.assertIn("ggml_vk_buffer_copy_async(subctx, ctx->fa_mask_diag_snapshot", fa)
        self.assertIn("ctx->fa_mask_diag_pending = true;", fa)
        flush = self.cpp.split("static void ggml_vk_fa_mask_diag_flush(", 1)[1].split(
            "static vk_device_architecture", 1
        )[0]
        self.assertIn("ggml_vk_buffer_read(ctx->fa_mask_diag_snapshot", flush)
        self.assertIn("refusing overwrite", flush)
        self.assertIn('".bin"', flush)
        self.assertIn('".json"', flush)
        sync = self.cpp.split("void ggml_vk_synchronize(", 1)[1].split(
            "static void ggml_backend_vk_synchronize(", 1
        )[0]
        self.assertIn("ggml_vk_fa_mask_diag_flush(ctx);", sync)
        self.assertIn("ggml_vk_destroy_buffer(ctx->fa_mask_diag_snapshot)", self.cpp)
        self.assertIn("fa_mask_diag_snapshot;", self.types)

    def test_short_only_smoke_without_rgp_trace(self):
        self.assertIn("Context          = 2048", self.plan)
        self.assertIn("PromptTokens     = @(1024)", self.plan)
        self.assertIn("Qcur-19", self.plan)
        self.assertIn("GGML_VK_FA_MASK_DIAG = '1'", self.plan)
        self.assertIn("GGML_VK_FA_RGP_MARKERS            = $null", self.plan)
        self.assertIn("GGML_VK_FA_DISPATCH_TRACE         = $null", self.plan)
        self.assertNotIn("65536", self.plan)


if __name__ == "__main__":
    unittest.main()
