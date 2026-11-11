"""Static contracts for the default-OFF HIP MMQ PP diagnostic."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MMQ = ROOT / "ggml" / "src" / "ggml-cuda" / "mmq.cu"
FA = ROOT / "ggml" / "src" / "ggml-cuda" / "fattn.cu"
SURVEY = ROOT / "ggml" / "src" / "ggml-cuda" / "evox2-hip-fa-survey.cuh"
PLAN = ROOT / "tools" / "evox2" / "benchmark" / "configs" / "qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1"
PREPARE = ROOT / "tools" / "evox2" / "benchmark" / "prepare-code-64k-cli-prompt.py"


class RocmMmqHostTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mmq = MMQ.read_text(encoding="utf-8")
        cls.fa = FA.read_text(encoding="utf-8")
        cls.survey = SURVEY.read_text(encoding="utf-8")
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

    def test_rgp_anchor_is_explicit_and_layer_specific(self):
        self.assertIn('GGML_HIP_RGP_ANCHOR', self.mmq)
        self.assertIn('GGML_HIP_RGP_ANCHOR', self.fa)
        self.assertIn('GGML_HIP_RGP_ANCHOR_KV', self.fa)
        self.assertIn('evox2_hip_anchor_moe_layer19<<<128, 64, 0, stream>>>();', self.mmq)
        self.assertIn('evox2_hip_anchor_fa_layer19<<<128, 64, 0, ctx.stream()>>>();', self.fa)
        self.assertIn('if (ggml_hip_rgp_mmq_anchor_enabled() && (ne12 == 512 || ne12 == 1024))', self.mmq)
        self.assertIn('std::strcmp(value, "1") == 0', self.mmq)
        self.assertIn('std::strcmp(value, "1") == 0', self.fa)
        self.assertIn("GGML_HIP_RGP_ANCHOR = '0'", self.plan)
        self.assertEqual(self.plan.count("Name = 'rgp-anchor'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_ANCHOR = '1'"), 12)

    def test_fa_survey_is_independent_opt_in(self):
        self.assertIn('#pragma once', self.survey)
        self.assertIn('#if defined(GGML_USE_HIP)', self.survey)
        self.assertIn('GGML_HIP_RGP_FA_SURVEY', self.survey)
        self.assertIn('std::strcmp(env, "1") == 0', self.survey)
        self.assertIn('#include "evox2-hip-fa-survey.cuh"', self.fa)
        self.assertIn('evox2_hip_fa_survey::enabled()', self.fa)
        self.assertIn('evox2_hip_fa_survey::submit(k->ne[1], q->ne[1], layer, ctx.stream());', self.fa)
        self.assertIn('static void submit(int64_t kv, int64_t n, long layer, cudaStream_t stream)', self.survey)
        self.assertNotIn('ggml_tensor', self.survey)

    def test_fa_survey_kv_bands_and_layer_grid(self):
        self.assertIn('kv_band_tokens = 4096', self.survey)
        self.assertIn('max_kv_band = 64', self.survey)
        self.assertEqual(49152 // 4096, 12)
        self.assertIn('layer_grid_base = 129', self.survey)
        self.assertIn('unknown_layer_blocks = 128', self.survey)
        self.assertIn('layer_grid_base + (int) layer', self.survey)
        self.assertIn('std::strstr(q->name, "Qcur-")', self.fa)
        cases = re.findall(r'case (\d+): evox2_hip_fa_survey_kv_band<(\d+)>', self.survey)
        self.assertEqual(cases, [(str(n), str(n)) for n in range(65)])
        self.assertIn('evox2_hip_fa_survey_kv_overflow', self.survey)
        self.assertIn('evox2_hip_fa_survey_v1 band=%d', self.survey)

    def test_fa_survey_does_not_sync_or_read_gpu_data(self):
        for forbidden in (
            'cudaStreamSynchronize', 'cudaDeviceSynchronize',
            'cudaMemcpy', 'hipMemcpy', 'cudaEvent', 'hipEvent',
            'cudaMalloc', 'hipMalloc',
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.survey)

    def test_survey_and_exact_kv_anchor_can_be_enabled_together(self):
        self.assertEqual(self.plan.count("Name = 'rgp-survey-anchor'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_FA_SURVEY = '1'"), 12)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_ANCHOR = '1'"), 12)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_ANCHOR_KV = '49152'"), 12)
        self.assertIn("GGML_HIP_MMQ_TRACE = '0'", self.plan)
        self.assertIn("GGML_HIP_FA_TRACE = '0'", self.plan)

    def test_fa_survey_fine_mode_is_opt_in_and_portable(self):
        self.assertIn('GGML_HIP_RGP_FA_SURVEY_FINE_BAND', self.survey)
        self.assertIn('GGML_HIP_RGP_FA_SURVEY_FINE_LAYER', self.survey)
        self.assertIn('fine_slot_tokens = 512', self.survey)
        self.assertIn('band >= 0 && band == fine_band()', self.survey)
        self.assertIn('layer == fine_layer()', self.survey)
        self.assertIn('evox2_hip_fa_survey_fine_v1', self.survey)
        cases = re.findall(r'case (\d+): evox2_hip_fa_survey_kv_slot<(\d+)>', self.survey)
        self.assertEqual(cases, [(str(n), str(n)) for n in range(8)])
        self.assertNotIn('ggml_tensor', self.survey)
        self.assertEqual(self.plan.count("Name = 'rgp-survey-fine'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_FA_SURVEY_FINE_BAND = '12'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_FA_SURVEY_FINE_LAYER = '19'"), 4)
        self.assertIn('GGML_HIP_RGP_FA_SURVEY_FINE_BAND = $null', self.plan)
        self.assertIn('GGML_HIP_RGP_FA_SURVEY_FINE_LAYER = $null', self.plan)

    def test_fa_survey_matrix_variant_is_separate(self):
        self.assertEqual(self.plan.count("Name = 'rgp-survey'"), 4)
        self.assertEqual(self.plan.count("GGML_HIP_RGP_FA_SURVEY = '1'"), 12)
        self.assertIn("GGML_HIP_RGP_FA_SURVEY = '0'", self.plan)
        self.assertIn("GGML_HIP_RGP_ANCHOR = '0'", self.plan)
        self.assertIn("GGML_HIP_FA_TRACE = '0'", self.plan)
        self.assertIn("GGML_HIP_MMQ_TRACE = '0'", self.plan)

    def test_reuses_existing_fa_trace(self):
        self.assertIn('GGML_HIP_FA_TRACE_KV', self.fa)
        self.assertIn('GGML_HIP_FA_TRACE_LAYER', self.fa)
        self.assertIn('evox2_hip_fa_trace_v1', self.fa)

    def test_plan_keeps_clean_capture_separate(self):
        self.assertEqual(len(re.findall(r"Name = 'pp64k-oldiq[34]-ub(?:512|1024)'", self.plan)), 4)
        self.assertEqual(self.plan.count("Name = 'host-trace'"), 4)
        self.assertEqual(self.plan.count("Name = 'rgp-clean'"), 4)
        self.assertEqual(self.plan.count("Name = 'rgp-anchor'"), 4)
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
