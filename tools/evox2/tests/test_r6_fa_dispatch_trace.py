"""Static source-contract tests for r6 opt-in CPU Vulkan FA dispatch trace.

These tests are not native Windows builds or RGP ordinal calibration.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
COMMON = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan-common.h"
CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-gate1-20261105.psd1"


class R6FaDispatchTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.common = COMMON.read_text(encoding="utf-8")
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")

    def test_exact_literal_one_and_atomic_ordinal(self):
        self.assertIn('std::getenv("GGML_VK_FA_DISPATCH_TRACE")', self.common)
        self.assertIn('std::strcmp(env, "1") == 0', self.common)
        self.assertIn("static std::atomic<uint64_t> ordinal {0};", self.common)
        self.assertIn("fetch_add(1, std::memory_order_relaxed) + 1", self.common)

    def test_count_is_adjacent_to_actual_dispatch(self):
        body = self.common.split("inline void ggml_vk_dispatch_pipeline(", 1)[1]
        self.assertIn("uint64_t * cpu_dispatch_ordinal = nullptr", body)
        pos = body.index("ggml_vk_fa_dispatch_trace_ordinal().fetch_add")
        dispatch_pos = body.index("subctx->s->buffer->buf.dispatch(wg0, wg1, wg2);", pos)
        self.assertLess(dispatch_pos - pos, 300)
        self.assertIn("*cpu_dispatch_ordinal = ordinal;", body[pos:dispatch_pos])
        self.assertNotIn("ggml_vk_synchronize(", body[pos:dispatch_pos])
        self.assertNotIn("waitForFences(", body[pos:dispatch_pos])

    def test_fa_event_log_contains_real_dispatch_metadata(self):
        body = self.cpp.split("static void ggml_vk_fa_rgp_dispatch(", 1)[1].split(
            "void ggml_vk_flash_attn(", 1
        )[0]
        self.assertEqual(body.count("ggml_vk_dispatch_pipeline("), 2)
        self.assertIn("ordinal_out = host_trace ? &cpu_dispatch_ordinal : nullptr", body)
        self.assertIn("ggml_vk_debug_label region(subctx, label, groups[0], groups[1], groups[2]);", body)
        self.assertIn("evox2_vk_fa_dispatch_v1 event=", body)
        self.assertIn("cpu_dispatch_ordinal=", body)
        for marker in ("stage=", "shader=", " q=", " KV=", " N=", " Br=", " Bc=", "n_kv_max=", "wg=("):
            self.assertIn(marker, body)
        self.assertIn("max_fa_events = 128", body)
        self.assertIn("truncated_after=", body)
        for forbidden in ("ggml_vk_synchronize(", "ggml_vk_sync_buffers(", "vkDeviceWaitIdle",
                          "ggml_vk_buffer_read(", "ggml_vk_buffer_copy"):
            self.assertNotIn(forbidden, body)

    def test_graph_logging_is_bounded_and_has_no_added_gpu_wait(self):
        body = self.cpp.split("static ggml_status ggml_backend_vk_graph_compute(", 1)[1].split(
            "void ggml_vk_graph_optimize(", 1
        )[0]
        self.assertIn("evox2_vk_graph_dispatch_v1 state=begin", body)
        self.assertIn("evox2_vk_graph_dispatch_v1 state=end", body)
        self.assertEqual(body.count("trace_graph_id <= 16"), 2)
        self.assertIn("cpu_dispatch_count=", body)
        self.assertIn("fa_events=", body)
        self.assertEqual(body.count("ggml_vk_synchronize(ctx);"), 1)

    def test_short_smoke_variant_isolated_from_baseline(self):
        self.assertIn("GGML_VK_FA_DISPATCH_TRACE           = $null", self.plan)
        self.assertEqual(self.plan.count("GGML_VK_FA_DISPATCH_TRACE = '1'"), 1)
        self.assertIn("Name = 'hosttrace-on'", self.plan)
        self.assertIn("R6PpFaRgpVulkan", self.plan)
        self.assertIn("Context          = 2048", self.plan)
        self.assertIn("PromptTokens     = @(1024)", self.plan)
        self.assertNotIn("65536", self.plan)


if __name__ == "__main__":
    unittest.main()
