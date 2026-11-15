"""Static contracts for experimental gfx1151 Q6_K Dense BLAS/MMQ routes."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CUDA = ROOT / "ggml/src/ggml-cuda/ggml-cuda.cu"
TESTS = ROOT / "tests/test-backend-ops.cpp"


class Q6KDenseRouteContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cuda = CUDA.read_text(encoding="utf-8")
        cls.backend = TESTS.read_text(encoding="utf-8")

    def test_exact_opt_in_and_gpu_type_gate(self):
        self.assertIn('std::getenv("GGML_HIP_Q6K_DENSE_ROUTE")', self.cuda)
        self.assertIn('std::strcmp(env, "blas") == 0', self.cuda)
        self.assertIn('std::strcmp(env, "mmq") == 0', self.cuda)
        self.assertIn("#if defined(GGML_USE_HIP)", self.cuda)
        self.assertIn("cc != GGML_CUDA_CC_OFFSET_AMD + 0x1151", self.cuda)
        self.assertIn("src0->type != GGML_TYPE_Q6_K", self.cuda)

    def test_only_intended_shapes_and_batch(self):
        for text in (
            "src0->ne[0] == 2560 && src0->ne[1] == 12288",
            "src0->ne[0] == 6144 && src0->ne[1] == 2560",
            "src1->ne[1] != 256 && src1->ne[1] != 512 && src1->ne[1] != 1024",
            "src0->ne[2] != 1",
            "src1->ne[2] != 1",
            "!ggml_is_contiguous(src0)",
            "!ggml_is_contiguous(src1)",
            "src0->view_src",
        ):
            with self.subTest(text=text):
                self.assertIn(text, self.cuda)

    def test_existing_unsupported_path_guard_precedes_override(self):
        start = self.cuda.index("static void ggml_cuda_mul_mat(ggml_backend_cuda_context")
        end = self.cuda.index("// returns true when ggml_cuda_mul_mat_id", start)
        dispatch = self.cuda[start:end]
        self.assertLess(dispatch.index("if (bad_padding_clear || src1->type"), dispatch.index("evox2_q6k_dense_route(src0"))
        self.assertIn("smpbo >= 48 * 1024", dispatch)
        self.assertIn('evox2_dense_gemm_trace::record(src0, src1, dst, ctx.device, "mmq")', dispatch)
        self.assertIn("ggml_cuda_mul_mat_cublas(ctx, src0, src1, dst)", dispatch)
        self.assertIn("ggml_cuda_mul_mat_q(ctx, src0, src1, nullptr, dst)", dispatch)

    def test_six_filtered_perf_and_correctness_cases(self):
        self.assertIn("struct test_q6k_dense_route : public test_mul_mat", self.backend)
        self.assertIn('return "Q6K_DENSE_ROUTE";', self.backend)
        self.assertIn("test_q6k_dense_route(12288, n, 2560)", self.backend)
        self.assertIn("test_q6k_dense_route(2560, n, 6144)", self.backend)
        self.assertIn("for (int64_t n : {256, 512, 1024})", self.backend)
        self.assertIn("{0, 1, 2, 3}, 0, 1, false, 0, 0, 0, true", self.backend)


if __name__ == "__main__":
    unittest.main()
