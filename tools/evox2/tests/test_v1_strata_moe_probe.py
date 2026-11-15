"""Static source contracts and standalone parsing for the v1.0.0 HIP MoE diagnostic."""

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CUDA = ROOT / "ggml/src/ggml-cuda/ggml-cuda.cu"
MMQ = ROOT / "ggml/src/ggml-cuda/mmq.cu"
TRACE = ROOT / "ggml/src/ggml-cuda/evox2-moe-trace.cuh"
BACKEND = ROOT / "tests/test-backend-ops.cpp"
PARSER = ROOT / "tools/evox2/benchmark/summarize-moe-dispatch.py"


def load_parser():
    spec = importlib.util.spec_from_file_location("moe_dispatch_summary", PARSER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MoeProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cuda = CUDA.read_text(encoding="utf-8")
        cls.mmq = MMQ.read_text(encoding="utf-8")
        cls.trace = TRACE.read_text(encoding="utf-8")
        cls.backend = BACKEND.read_text(encoding="utf-8")
        cls.parser = load_parser()

    def test_trace_is_hip_only_and_exact_opt_in(self):
        self.assertIn("#if defined(GGML_USE_HIP)", self.trace)
        self.assertIn('std::strcmp(env, "1") == 0', self.trace)
        self.assertIn("if (!enabled() || ids == nullptr) return;", self.trace)
        self.assertIn("GGML_HIP_MOE_TRACE_LAYER", self.trace)
        self.assertIn("GGML_HIP_MOE_TRACE_N", self.trace)
        self.assertIn("GGML_HIP_MOE_TRACE_LIMIT", self.trace)

    def test_trace_does_not_launch_or_sync_gpu(self):
        for name in ("cudaStreamSynchronize", "hipStreamSynchronize", "cudaDeviceSynchronize",
                     "cudaMemcpy", "hipMemcpy", "cudaEvent", "hipEvent", "__global__",
                     "cudaLaunchKernel", "hipLaunchKernel"):
            with self.subTest(forbidden=name):
                self.assertNotIn(name, self.trace)

    def test_trace_includes_all_moe_dispatch_paths(self):
        self.assertIn('#include "ggml-cuda/evox2-moe-trace.cuh"', self.cuda)
        self.assertIn('#include "evox2-moe-trace.cuh"', self.mmq)
        self.assertIn('trace_moe("mmvq");', self.cuda)
        self.assertIn('trace_moe("mmvf");', self.cuda)
        self.assertIn('trace_moe("mmf");', self.cuda)
        self.assertIn('trace_moe("host_fallback");', self.cuda)
        self.assertIn('evox2_moe_trace::record(src0, src1, ids, dst, ctx.device, "mmq", J_best, fallback, prec_src1);', self.mmq)
        self.assertLess(self.mmq.index("GGML_ASSERT(J_best > 0);"),
                        self.mmq.index('evox2_moe_trace::record('))

    def test_full_moe_test_uses_iq2s_gate_up_and_iq4nl_down(self):
        self.assertIn("struct test_moe_gate_up_down : public test_case", self.backend)
        self.assertEqual(self.backend.count("GGML_TYPE_IQ2_S, n_embd, n_ff, n_experts"), 2)
        self.assertIn("GGML_TYPE_IQ4_NL, n_ff, n_embd, n_experts", self.backend)
        self.assertIn("ggml_swiglu_split", self.backend)
        self.assertIn("MOE_GATE_UP_DOWN", self.backend)
        self.assertIn("test_moe_gate_up_down(n)", self.backend)

    def test_parser_summarizes_and_detects_truncation(self):
        raw = [
            "prefix evox2_moe_dispatch_v1 seq=1 layer=19 role=gate path=mmq N=1024 weight_type=iq2_s J=32",
            "evox2_moe_dispatch_v1 seq=2 layer=19 role=up path=mmq N=1024 weight_type=iq2_s J=32",
            "evox2_moe_dispatch_v1 seq=3 layer=19 role=down path=mmq N=1024 weight_type=iq4_nl J=32",
            "evox2_moe_dispatch_v1 truncated_after=2048",
        ]
        records, truncated = self.parser.parse_records(raw)
        self.assertTrue(truncated)
        self.assertEqual(len(records), 3)
        result = self.parser.aggregate(records)
        self.assertEqual(result[(19, "gate", "iq2_s", "mmq", 1024, 32)], 1)
        self.assertEqual(result[(19, "down", "iq4_nl", "mmq", 1024, 32)], 1)
        self.assertNotIn(2, {row["layer"] for row in records})


class Iq2sFusionSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mmq_header = (ROOT / "ggml/src/ggml-cuda/mmq.cuh").read_text(encoding="utf-8")
        cls.loader = (ROOT / "ggml/src/ggml-cuda/mmq-load-tiles.cuh").read_text(encoding="utf-8")
        cls.cuda = CUDA.read_text(encoding="utf-8")
        cls.mmq = MMQ.read_text(encoding="utf-8")
        cls.backend = BACKEND.read_text(encoding="utf-8")

    def test_explicit_hip_only_opt_in_and_exact_device(self):
        self.assertIn('std::getenv("GGML_HIP_MOE_IQ2S_FUSION")', self.cuda)
        self.assertIn('std::strcmp(env, "1") == 0', self.cuda)
        self.assertIn('GGML_CUDA_CC_OFFSET_AMD + 0x1151', self.cuda)
        self.assertIn('up->op == GGML_OP_MUL_MAT_ID', self.cuda)
        self.assertIn('ggml_get_glu_op(glu) == GGML_GLU_OP_SWIGLU', self.cuda)
        self.assertIn('y->ne[1] == 1', self.cuda)
        self.assertIn('if (x_up->type == GGML_TYPE_IQ2_S)', self.cuda)
        self.assertIn('#if defined(GGML_USE_HIP)', self.cuda)

    def test_loader_reads_gate_and_up_interleaved(self):
        self.assertIn('ggml_cuda_mmq_load_tiles_iq2_s<type, J, fallback, has_fusion>', self.mmq_header)
        self.assertIn('ggml_cuda_mmq_load_tiles_iq2_s<type, J, fallback, false>', self.mmq_header)
        self.assertIn('ggml_cuda_mmq_x_row<block_iq2_s, has_fusion>', self.loader)
        self.assertIn('defined(AMD_WMMA_256B_AVAILABLE)', self.mmq_header)
        self.assertIn('ggml_cuda_mmq_write_back_mma<type, J, fallback, prec_src1, has_fusion>', self.mmq_header)

    def test_accumulator_pairs_up_gate_in_same_wmma256_lane(self):
        # WMMA256 C tile is 16x16 with 8 values per lane. For J-major output,
        # get_i(l) = 2*l + lane//16 and get_j(l) = lane%16.
        for lane in range(32):
            for value in range(4):
                up_i = 2*value + lane//16
                gate_i = 2*(value+4) + lane//16
                self.assertEqual(gate_i, up_i+8)
        self.assertIn('sum[sum_index + tile_C::ne/2]', self.mmq_header)

    def test_fused_dispatch_logging(self):
        self.assertIn('"mmq_iq2s_fused"', self.mmq)
        self.assertIn('gate && src0->type == GGML_TYPE_IQ2_S', self.mmq)
        self.assertIn('test_moe_gate_up_down(n, 512, 10)', self.backend)


if __name__ == "__main__":
    unittest.main()
