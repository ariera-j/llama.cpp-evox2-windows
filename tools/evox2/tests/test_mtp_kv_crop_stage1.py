#!/usr/bin/env python3
"""Static checks for the experimental Stage-A Qwen4Exp MTP prefill graph crop.

These checks do NOT establish runtime correctness or actual GPU speedups.
Run from anywhere: python tools/evox2/tests/test_mtp_kv_crop_stage1.py
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
QWEN_PATH = ROOT / "src/models/qwen4exp.cpp"
GRAPH_PATH = ROOT / "src/llama-graph.cpp"


class StageAKvCropSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.qwen = QWEN_PATH.read_text(encoding="utf-8")
        cls.graph = GRAPH_PATH.read_text(encoding="utf-8")
        cls.context = (ROOT / "src/llama-context.cpp").read_text(encoding="utf-8")
        cls.mtp = cls.qwen.split(
            "llama_model_qwen4exp::graph_mtp::graph_mtp", 1
        )[1].split("llama_model_qwen4exp::graph::build_qkvz", 1)[0]

    def test_opt_in_is_default_off_and_exact(self):
        self.assertIn('std::getenv("LLAMA_MTP_DRAFT_PREFILL_KV_CROP")', self.mtp)
        self.assertIn('std::strcmp(kv_crop_env, "1") == 0', self.mtp)

    def test_semantic_guard_is_narrow(self):
        for requirement in (
            "n_outputs == 0",
            "cparams.embeddings_nextn && cparams.embeddings_nextn_masked",
            "!cparams.training",
            "!cparams.kv_unified",
            "ubatch.n_seqs_unq == 1",
            "hparams.dsv4_compress_ratios[il] == 0",
        ):
            with self.subTest(requirement=requirement):
                self.assertIn(requirement, self.mtp)
        # Forward-porting to upstream embd_state/vision should not change the
        # definition of a zero-output Draft catch-up graph.
        gate = self.mtp.split("const bool draft_prefill_kv_crop =", 1)[1].split(";", 1)[0]
        self.assertNotIn("ubatch.token", gate)
        self.assertNotIn("ubatch.embd", gate)

    def test_unneeded_output_ids_are_not_registered(self):
        self.assertIn(
            "draft_prefill_kv_crop ? nullptr : build_inp_out_ids()",
            self.mtp,
        )

    def test_cache_writes_expand_before_root_crop(self):
        attn = self.mtp.index("cur    = build_layer_attn(")
        early_return = self.mtp.index("if (draft_prefill_kv_crop) {\n        return;")
        ffn = self.mtp.index("cur    = build_layer_ffn(")
        full_hidden = self.mtp.index("ggml_build_forward_expand(gf, res->t_h_nextn)")
        self.assertLess(attn, early_return)
        self.assertLess(early_return, ffn)
        self.assertLess(early_return, full_hidden)
        build_attn = self.graph.split(
            "ggml_tensor * llm_graph_context::build_attn(\n"
            "        llm_graph_input_attn_kv * inp", 1
        )[1].split("static std::unique_ptr<llm_graph_input_attn_k>", 1)[0]
        self.assertIn("mctx_cur->cpy_k(ctx0, k_cur, k_idxs, il)", build_attn)
        self.assertIn("mctx_cur->cpy_v(ctx0, v_cur, v_idxs, il)", build_attn)
        self.assertIn("ggml_build_forward_expand(gf, q_cur)", build_attn)

    def test_required_draft_memory_and_full_generation_remain(self):
        self.assertIn("ggml_build_forward_expand(gf, inp_hyb->get_recr()->s_copy)", self.mtp)
        self.assertIn("ggml_build_forward_expand(gf, res->t_h_nextn)", self.mtp)
        self.assertIn("res->t_logits = cur", self.mtp)
        self.assertIn("hparams.n_layer_nextn == 1", self.mtp)
        self.assertIn("hparams.dsv4_compress_ratios[il] > 0", self.mtp)

    def test_unallocated_hybrid_mask_is_skipped(self):
        setter = self.graph.split(
            "void llm_graph_input_mem_hybrid::set_input", 1
        )[1].split("bool llm_graph_input_mem_hybrid::can_reuse", 1)[0]
        self.assertRegex(
            setter,
            r"if \(inp_attn->self_kq_mask && inp_attn->self_kq_mask->buffer\)"
            r"\s*\{\s*mctx->get_attn\(\)->set_input_kq_mask",
        )


    def test_active_catchup_diagnostic_is_scoped_and_opt_in(self):
        ctx = self.context
        self.assertIn('std::getenv("LLAMA_MTP_KV_CROP_DIAG")', ctx)
        self.assertIn('std::strcmp(env, "1") == 0', ctx)
        self.assertIn('gtype == LLM_GRAPH_TYPE_DECODER_MTP', ctx)
        self.assertIn('model.arch == LLM_ARCH_QWEN4EXP && n_outputs == 0', ctx)
        self.assertIn('sample < 8', ctx)
        # The instrumented site is the actual compute graph, not sched_reserve().
        proc = ctx.split("llm_graph_result * llama_context::process_ubatch", 1)[1]
        self.assertLess(proc.index("ggml_backend_sched_alloc_graph"), proc.index("mtp_kv_crop_graph_v1"))
        self.assertLess(proc.index("mtp_kv_crop_graph_v1"), proc.index("res->set_inputs(&ubatch)"))
        self.assertIn("ggml_graph_n_nodes(gf)", proc)
        self.assertIn("ggml_graph_node(gf, i)", proc)

    def test_active_catchup_counts_cache_writes_and_fa(self):
        ctx = self.context
        for fragment in (
            "GGML_OP_FLASH_ATTN_EXT",
            "GGML_OP_MUL_MAT_ID",
            "GGML_OP_SET_ROWS",
            '"attn_inp_k_idxs"',
            '"attn_inp_v_idxs"',
            'n_k_writes',
            'n_v_writes',
            'n_fa',
            'kv_slots',
            'graph_reused',
            'crop_requested',
            'crop_applied',
            '!res->get_logits() && !res->get_h_nextn()',
            'std::atomic<unsigned> logged{0}',
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, ctx)

    def test_diagnostic_plan_isolated_from_performance_jobs(self):
        plan = (ROOT / "tools/evox2/benchmark/configs/"
                "qwen38-r5-mtp-kv-crop-stage1.psd1").read_text(encoding="utf-8")
        self.assertIn("LLAMA_MTP_KV_CROP_DIAG             = $null", plan)
        self.assertIn("Name = 'stage1-diag-short'", plan)
        self.assertIn("BuildKeys = @('R5MtpKvCropDiagVulkan')", plan)
        diag = plan.split("Name = 'stage1-diag-short'", 1)[1]
        self.assertIn("LLAMA_MTP_KV_CROP_DIAG = '1'", diag)
        self.assertIn("Name = 'A-diag'", diag)
        self.assertIn("Name = 'B-diag'", diag)
        self.assertNotIn("LLAMA_MTP_KV_CROP_DIAG = '1'",
                         plan.split("Name = 'stage1-diag-short'", 1)[0])

    def test_diagnostic_does_not_change_crop_guard_or_normal_path(self):
        ctx = self.context
        self.assertIn('const bool draft_prefill_kv_crop =', self.mtp)
        self.assertRegex(self.mtp, r"if \(draft_prefill_kv_crop\) \{\s*return;")
        self.assertIn('const bool crop_applied = !res->get_logits() && !res->get_h_nextn();', ctx)
        self.assertIn('const auto status = graph_compute(res->get_gf()', ctx)


if __name__ == "__main__":
    unittest.main()
