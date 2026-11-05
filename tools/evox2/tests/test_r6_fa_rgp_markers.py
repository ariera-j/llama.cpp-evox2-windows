"""Static source/plan tests for r6 PP Flash Attention RGP marker Gate 1.

These checks are *not* Windows C++ compilation or runtime RGP visibility tests.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
VK_CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-gate1-20261105.psd1"


class R6FaRgpMarkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = VK_CPP.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")

    def test_opt_in_exact_literal_one(self):
        self.assertIn('std::getenv("GGML_VK_FA_RGP_MARKERS")', self.cpp)
        self.assertIn('std::strcmp(env, "1") == 0', self.cpp)
        self.assertIn("const bool fa_rgp_markers = ggml_vk_fa_rgp_markers_enabled();", self.cpp)

    def test_ext_requested_only_for_marker_or_existing_debug(self):
        self.assertIn("const bool debug_utils_available = ggml_vk_instance_debug_utils_ext_available(instance_extensions);", self.cpp)
        self.assertIn('(getenv("GGML_VK_DEBUG_MARKERS") != nullptr || fa_rgp_markers)', self.cpp)
        self.assertIn("if (fa_rgp_markers && !debug_utils_available)", self.cpp)
        self.assertIn("ggml_vulkan: FA RGP markers enabled (VK_EXT_debug_utils, label prefix EVOX2_FA_)", self.cpp)
        self.assertIn("ggml_vk_debug_label region(subctx, label);", self.cpp)

    def test_five_dispatch_stages_with_exact_kernel_metadata(self):
        main = self.cpp.split("void ggml_vk_flash_attn(", 1)[1].split(
            "static vk_conv_shapes ggml_vk_conv_select_shape(", 1
        )[0]
        for stage in ("MASK_OPT", "SPARSE", "MAIN_SPLIT", "SPLIT_REDUCE", "MAIN"):
            self.assertEqual(
                main.count(f'"{stage}", q->name, KV, N, Br, Bc, n_kv_max);'),
                1, stage,
            )
        helper = self.cpp.split("static void ggml_vk_fa_rgp_dispatch(", 1)[1].split(
            "void ggml_vk_flash_attn(", 1
        )[0]
        for key in ('shader=', ' KV=', ' N=', ' Br=', ' Bc=', ' n_kv_max=', ' q='):
            self.assertIn(key, helper)
        self.assertIn(
            "ggml_vk_dispatch_pipeline(ctx, subctx, pipeline, buffers, pc, groups);",
            helper,
        )
        self.assertEqual(helper.count("ggml_vk_dispatch_pipeline("), 2)

    def test_no_new_sync_or_mask_readback(self):
        helper = self.cpp.split("static void ggml_vk_fa_rgp_dispatch(", 1)[1].split(
            "void ggml_vk_flash_attn(", 1
        )[0]
        for disallowed in (
            "ggml_vk_sync_buffers(", "ggml_vk_synchronize(", "vkQueueWaitIdle",
            "ggml_vk_buffer_read(", "ggml_vk_buffer_copy", "vkDeviceWaitIdle",
        ):
            self.assertNotIn(disallowed, helper)
        self.assertNotIn("GGML_VK_FA_MASK_DIAG=1", self.plan)

    def test_safe_smoke_only_and_distinct_binary(self):
        self.assertIn("R6PpFaRgpVulkan", self.plan)
        self.assertNotIn("CombinedVulkan", self.plan)
        self.assertIn("Name = 'vulkan-fa-rgp-short'", self.plan)
        self.assertIn("Context          = 2048", self.plan)
        self.assertIn("PromptTokens     = @(1024)", self.plan)
        self.assertIn("NoWarmup         = $true", self.plan)
        self.assertIn("GGML_VK_QSA_UNION                   = '0'", self.plan)
        self.assertIn("GGML_VK_PERF_LOGGER                 = $null", self.plan)
        self.assertIn("GGML_VK_DEBUG_MARKERS               = $null", self.plan)
        self.assertEqual(self.plan.count("GGML_VK_FA_RGP_MARKERS = '1'"), 1)
        self.assertIn("Name = 'markers-off-control'", self.plan)
        self.assertIn("Name = 'markers-on'", self.plan)
        self.assertNotIn("65536", self.plan)

if __name__ == "__main__":
    unittest.main()
