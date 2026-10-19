"""Static source-contract checks for investigation-only Vulkan MTP RGP markers.

These tests do not replace an actual Vulkan/Windows build or native RGP smoke.
They are deliberately limited to source/plan wiring and accidental sync regressions.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
VK_CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
VK_TYPES = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan-types.h"
RGP_PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r5-mtp-pp-rgp-64k.psd1"


class MtpRgpMarkerSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = VK_CPP.read_text(encoding="utf-8")
        cls.types = VK_TYPES.read_text(encoding="utf-8")
        cls.plan = RGP_PLAN.read_text(encoding="utf-8")

    def test_literal_opt_in_and_extension_enable(self):
        self.assertIn('std::getenv("GGML_VK_MTP_PP_RGP_MARKERS")', self.cpp)
        self.assertIn('std::strcmp(env, "1") == 0', self.cpp)
        self.assertIn("getenv(\"GGML_VK_DEBUG_MARKERS\") != nullptr || mtp_rgp_markers", self.cpp)
        self.assertIn("if (mtp_rgp_markers && !debug_utils_available)", self.cpp)

    def test_target_draft_graph_detection_remains_a_hint(self):
        self.assertIn('std::strstr(name, "mtp_hnorm")', self.cpp)
        self.assertIn('std::strstr(name, "mtp_eh_proj")', self.cpp)
        self.assertIn('std::strstr(name, "hc_init")', self.cpp)
        self.assertIn('ctx->mtp_rgp_graph_role = "unknown"', self.cpp)
        self.assertIn('EVOX2_MTP_GRAPH role=', self.cpp)
        self.assertIn('const char * mtp_rgp_graph_role = "unknown"', self.types)

    def test_gpu_stage_names_and_no_new_sync_in_wrapper(self):
        for marker in (
            '"QSA_UNION"', '"QSA_GATHER"', '"QSA_MAIN"',
            '"MASK_OPT"', '"SPARSE"', '"MAIN_SPLIT"',
            '"SPLIT_REDUCE"', '"MAIN"',
        ):
            self.assertIn(marker, self.cpp)
        self.assertIn('EVOX2_MTP_MATMUL role=', self.cpp)
        self.assertIn('ggml_vk_debug_label(vk_context & ctx, const std::string & region_name)', self.types)
        self.assertIn('ggml_vk_debug_label::ggml_vk_debug_label(vk_context & ctx, const std::string & region_name)', self.cpp)
        wrapper = self.cpp.split("static void ggml_vk_mtp_pp_rgp_dispatch(", 1)[1].split(
            "static bool ggml_vk_qsa_union(", 1
        )[0]
        self.assertIn("ggml_vk_dispatch_pipeline(ctx, subctx, pipeline, buffers, pc, groups);", wrapper)
        self.assertNotIn("ggml_vk_synchronize(", wrapper)
        self.assertNotIn("ggml_vk_sync_buffers(", wrapper)

    def test_diagnostic_matmul_label_closed_before_graph_node(self):
        self.assertIn("if (mtp_op_dbg) {\n        mtp_op_dbg->close();\n    }\n    dbg.close();", self.cpp)

    def test_plan_isolated_to_new_build_and_does_not_enable_perf_logger(self):
        self.assertIn("R5MtpRgpVulkan", self.plan)
        self.assertNotIn("R5Common001Vulkan", self.plan)
        self.assertEqual(self.plan.count("GGML_VK_MTP_PP_RGP_MARKERS = '1'"), 2)
        self.assertIn("GGML_VK_PERF_LOGGER              = $null", self.plan)
        self.assertIn("GGML_VK_DEBUG_MARKERS            = $null", self.plan)
        self.assertIn("Name = 'vulkan-64k'", self.plan)
        self.assertIn("InputKey = '64k'", self.plan)


if __name__ == "__main__":
    unittest.main()
