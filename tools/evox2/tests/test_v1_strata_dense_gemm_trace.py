"""Static checks and log parser tests for the v1 Dense GEMM dispatch probe."""

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CUDA = ROOT / "ggml/src/ggml-cuda/ggml-cuda.cu"
TRACE = ROOT / "ggml/src/ggml-cuda/evox2-dense-gemm-trace.cuh"
PARSER = ROOT / "tools/evox2/benchmark/summarize-dense-gemm.py"


class DenseGemmTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cuda = CUDA.read_text(encoding="utf-8")
        cls.header = TRACE.read_text(encoding="utf-8")
        spec = importlib.util.spec_from_file_location("evox2_dense_gemm_summary", PARSER)
        cls.parser = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.parser)

    def test_hip_only_and_disabled_by_default(self):
        self.assertIn("#if defined(GGML_USE_HIP)", self.header)
        self.assertIn('std::getenv("GGML_HIP_GEMM_TRACE")', self.header)
        self.assertIn('std::strcmp(enabled, "1") == 0', self.header)
        for var in ("GGML_HIP_GEMM_TRACE_LAYER", "GGML_HIP_GEMM_TRACE_N", "GGML_HIP_GEMM_TRACE_LIMIT"):
            self.assertIn(var, self.header)
        self.assertIn("dst->op != GGML_OP_MUL_MAT", self.header)

    def test_no_gpu_synchronization_or_readback(self):
        for forbidden in ("cudaDeviceSynchronize", "cudaStreamSynchronize", "cudaMemcpy", "hipMemcpy",
                          "__global__", "hipLaunchKernel", "cudaLaunchKernel"):
            with self.subTest(name=forbidden):
                self.assertNotIn(forbidden, self.header)

    def test_covers_all_regular_dense_paths_and_selected_blas_type(self):
        self.assertIn('#include "ggml-cuda/evox2-dense-gemm-trace.cuh"', self.cuda)
        for path in ("fwht", "mmvf", "mmvf_transposed", "mmf", "mmvq", "mmq_few", "mmq", "fp8", "blas"):
            with self.subTest(path=path):
                self.assertIn(f'"{path}"', self.cuda)
        self.assertIn('"blas", ggml_type_name(compute_type)', self.cuda)
        self.assertIn('const int cc = ggml_cuda_info().devices[ctx.device].cc;', self.cuda)

    def test_valid_rows_and_truncation(self):
        lines = [
            "prefix evox2_dense_gemm_v1 seq=1 device=0 layer=19 path=blas weight_type=q6_k "
            "activation_type=f32 dst_type=f32 compute_type=f16 K=2560 M=6144 N=1024 "
            "w2=1 w3=1 a2=1 a3=1 weight=blk.19.attn_q.weight activation=x dst=out",
            "evox2_dense_gemm_v1 seq=2 device=0 layer=19 path=mmq weight_type=q8_0 "
            "activation_type=f32 dst_type=f32 compute_type=- K=2560 M=2560 N=1024 "
            "weight=blk.19.attn_k.weight activation=x dst=out",
            "evox2_dense_gemm_v1 truncated_after=2048",
            "this is not a trace",
        ]
        rows, truncated = self.parser.parse_records(lines)
        self.assertTrue(truncated)
        self.assertEqual(len(rows), 2)
        summary = self.parser.aggregate(rows)
        self.assertEqual(summary[(19, "blk.19.attn_q.weight", "q6_k", "blas", "f16", 2560, 6144, 1024)], 1)
        self.assertEqual(summary[(19, "blk.19.attn_k.weight", "q8_0", "mmq", "-", 2560, 2560, 1024)], 1)

    def test_layer_parser_does_not_match_similar_layer(self):
        self.assertIn("return *p == '.' || *p == '\\0' ? layer : -1;", self.header)
        self.assertIn('get_layer(weight->name)', self.header)


if __name__ == "__main__":
    unittest.main()
