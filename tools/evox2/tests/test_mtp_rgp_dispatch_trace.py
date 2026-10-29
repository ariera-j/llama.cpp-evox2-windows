"""Static-source checks for the opt-in Vulkan RGP dispatch range calibration.

Must be followed by a real Windows Vulkan build and a native smoke:
CPU count can differ from RDP's absolute renderop index when other dispatch
paths are present or command-buffer submission is delayed/reordered.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
VK_COMMON = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan-common.h"
VK_CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r5-mtp-pp-rgp-dispatch-64k.psd1"


class MtpRgpDispatchTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.common = VK_COMMON.read_text(encoding="utf-8")
        cls.cpp = VK_CPP.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")

    def test_opt_in_only_with_literal_one(self):
        self.assertIn('std::getenv("GGML_VK_MTP_PP_RGP_DISPATCH_TRACE")', self.common)
        self.assertIn('std::strcmp(env, "1") == 0', self.common)
        self.assertIn("std::atomic<uint64_t> ordinal {0}", self.common)
        self.assertIn("std::memory_order_relaxed", self.common)

    def test_counter_on_exact_vkcmddispatch(self):
        self.assertIn("if (ggml_vk_mtp_rgp_dispatch_trace_enabled()) {", self.common)
        section = self.common.split("ggml_vk_mtp_rgp_dispatch_counter().fetch_add", 1)[1]
        self.assertIn("subctx->s->buffer->buf.dispatch(wg0, wg1, wg2);", section[:220])
        self.assertNotIn("waitForFences", section[:220])
        self.assertNotIn("synchronize", section[:220])

    def test_graph_role_and_bounded_dispatch_interval(self):
        self.assertIn('ctx->mtp_rgp_graph_role = "unknown"', self.cpp)
        self.assertIn('is_draft ? "draft" : (is_target ? "target" : "unknown")', self.cpp)
        self.assertIn('evox2_mtp_vk_graph_v1 role=', self.cpp)
        self.assertIn(' dispatch_begin=', self.cpp)
        self.assertIn(' dispatch_end=', self.cpp)
        self.assertIn(' dispatch_count=', self.cpp)
        self.assertIn(' n_nodes=', self.cpp)
        graph = self.cpp.split("static ggml_status ggml_backend_vk_graph_compute(", 1)[1].split(
            "static void ggml_backend_vk_graph_optimize(", 1
        )[0]
        self.assertIn("const uint64_t mtp_dispatch_first", graph)
        self.assertIn("if (mtp_dispatch_trace) {", graph)
        self.assertIn("return GGML_STATUS_SUCCESS;", graph)

    def test_new_build_key_and_only_calibration_jobs(self):
        self.assertIn("R5MtpRgpDispatchVulkan", self.plan)
        self.assertNotIn("R5Common001Vulkan", self.plan)
        self.assertNotIn("R5MtpRgpVulkan')", self.plan)
        self.assertEqual(self.plan.count("GGML_VK_MTP_PP_RGP_DISPATCH_TRACE = '1'"), 2)
        self.assertIn("GGML_VK_PERF_LOGGER              = $null", self.plan)
        self.assertIn("Name = 'vulkan-short'", self.plan)
        self.assertIn("Name = 'vulkan-64k'", self.plan)


if __name__ == "__main__":
    unittest.main()
