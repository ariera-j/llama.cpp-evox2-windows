"""Static contracts for the default-OFF HIP MMQ PP diagnostic."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MMQ = ROOT / "ggml" / "src" / "ggml-cuda" / "mmq.cu"
FA = ROOT / "ggml" / "src" / "ggml-cuda" / "fattn.cu"
PLAN = ROOT / "tools" / "evox2" / "benchmark" / "configs" / "qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1"
PREPARE = ROOT / "tools" / "evox2" / "benchmark" / "prepare-code-64k-cli-prompt.py"


class RocmMmqHostTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mmq = MMQ.read_text(encoding="utf-8")
        cls.fa = FA.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")
        cls.prepare = PREPARE.read_text(encoding="utf-8")

    def test_opt_in_is_exactly_one_and_hip_only(self):
        self.assertIn('#if defined(GGML_USE_HIP)', self.mmq)
        self.assertIn('std::strcmp(value, "1") == 0', self.mmq)
        self.assertIn('GGML_HIP_MMQ_TRACE_LAYER', self.mmq)
        self.assertIn('GGML_HIP_MMQ_TRACE_N', self.mmq)

    def test_mmq_metadata_is_logged_after_tile_selection(self):
        at = self.mmq.index('GGML_ASSERT(J_best > 0);')
        call = self.mmq.index('ggml_hip_mmq_trace_host(src0, src1, ids, dst, id, J_best, fallback, prec_src1);')
        self.assertGreater(call, at)
        self.assertIn('ids ? src1->ne[2] : src1->ne[1]', self.mmq)
        self.assertIn('ggml_type_name(src0->type)', self.mmq)
        self.assertIn('moe=%d J=%d', self.mmq)
        self.assertIn('if (match_id > 2048)', self.mmq)

    def test_diagnostic_has_no_gpu_sync_or_readback(self):
        begin = self.mmq.index('static void ggml_hip_mmq_trace_host(')
        end = self.mmq.index('\n#endif\n\nvoid ggml_cuda_mul_mat_q(', begin)
        helper = self.mmq[begin:end]
        for forbidden in ('cudaStreamSynchronize', 'cudaDeviceSynchronize', 'cudaMemcpy', 'hipMemcpy', 'cudaEvent', 'hipEvent', 'cudaLaunchKernel'):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, helper)

    def test_reuses_existing_fa_trace(self):
        self.assertIn('GGML_HIP_FA_TRACE_KV', self.fa)
        self.assertIn('GGML_HIP_FA_TRACE_LAYER', self.fa)
        self.assertIn('evox2_hip_fa_trace_v1', self.fa)

    def test_plan_keeps_clean_capture_separate(self):
        self.assertEqual(len(re.findall(r"Name = 'pp64k-oldiq[34]-ub(?:512|1024)'", self.plan)), 4)
        self.assertEqual(self.plan.count("Name = 'host-trace'"), 4)
        self.assertEqual(self.plan.count("Name = 'rgp-clean'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_MMQ_TRACE = '1'"), 4)
        self.assertIn("GGML_HIP_MMQ_TRACE = '0'", self.plan)
        self.assertIn("GGML_HIP_FA_TRACE = '0'", self.plan)
        self.assertIn("Context = 65536; InputKey = 'PPCode64kRgp'", self.plan)
        self.assertIn("QWEN4EXP_QSA_GATHER = '0'", self.plan)

    def test_fixture_preparation_tracks_hash_and_token_count(self):
        self.assertIn('llama-tokenize', self.prepare)
        self.assertIn('--show-count', self.prepare)
        self.assertIn('--no-bos', self.prepare)
        self.assertIn('source_sha256', self.prepare)
        self.assertIn('output_sha256', self.prepare)
        self.assertIn('if args.out.exists():', self.prepare)


if __name__ == "__main__":
    unittest.main()
