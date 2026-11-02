"""COMMON-005 r6 source-contract and pure-Python selection sanity tests.

No model, GPU, or HIP backend is executed by these tests. Native build,
real-output and targeted long-context tests remain mandatory.
"""

from pathlib import Path
import math
import struct
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "src" / "models" / "qwen4exp.cpp"
HEADER = ROOT / "src" / "models" / "models.h"
BENCH_MODULE = ROOT / "tools" / "evox2" / "benchmark" / "Evox2.Benchmark.psm1"
PLAN = ROOT / "tools" / "evox2" / "benchmark" / "configs" / "qwen38-r6-rocm-common005-gather-20261102.psd1"


def compact_pool_tail(pools, selected, scores, tail, n_kv):
    # Reference of the C++ graph formula: top blocks followed by tail;
    # invisible scores are -inf; n_kv is a sentinel, never gather it.
    candidates = [pools[i] for i in selected]
    flat = [index for pool in candidates for index in pool] + tail
    live = [1 if math.isfinite(scores[i]) and scores[i] >= 0 else 0
            for i in selected for _ in pools[i]]
    live.extend(1 if 0 <= index < n_kv else 0 for index in tail)
    indices = [index if yes else 0 for index, yes in zip(flat, live)]
    mask = [0.0 if yes else -65504.0 for yes in live]
    return indices, mask


class TestQsaCommon005(unittest.TestCase):
    def test_explicit_opt_in_default_off(self):
        src = SOURCE.read_text(encoding="utf-8")
        self.assertIn('std::getenv("QWEN4EXP_QSA_GATHER")', src)
        self.assertIn('env && std::strcmp(env, "1") == 0', src)
        self.assertIn('n_tokens == 1', src)
        self.assertIn('ubatch.n_seqs_unq == 1', src)
        self.assertIn('inp_kpool->n_kv <= (1u << 24)', src)
        self.assertIn('inp_kpool->n_kv / 4 >= inp_kpool->n_sel', src)
        self.assertIn('kc->type == GGML_TYPE_F16 && vc->type == GGML_TYPE_F16', src)

    def test_compact_graph_has_safe_indices_and_fallback(self):
        src = SOURCE.read_text(encoding="utf-8")
        hdr = HEADER.read_text(encoding="utf-8")
        self.assertIn('ggml_tensor ** gather_idx', hdr)
        self.assertIn('qsa_gather_safe_idx', src)
        self.assertIn('qsa_gather_mask', src)
        self.assertIn('qsa_k_gathered', src)
        self.assertIn('qsa_v_gathered', src)
        self.assertIn('qwen4exp_common005_v1 graph_built=compact', src)
        self.assertIn('if (gather_idx) {', src)
        self.assertIn('GGML_ASSERT(ggml_are_same_shape(sel, kq_mask))', src)
        self.assertIn('ggml_mul(ctx0,', src)
        self.assertIn('65504.0f, -65504.0f', src)
        self.assertIn('build_attn_mha(q, k_sel, v_sel, nullptr, sel', src)
        self.assertIn('build_attn_mha(q, k, v, nullptr, sel', src)

    def test_reference_pool_visibility_and_tail_sentinel(self):
        indices, mask = compact_pool_tail(
            pools=[[0, 1, 2, 3], [40, 41, 42, 43], [8, 9, 10, 11]],
            selected=[2, 1], scores=[2.0, float("-inf"), 0.0],
            tail=[63, 64, 64], n_kv=64)
        self.assertEqual(indices, [8, 9, 10, 11, 0, 0, 0, 0, 63, 0, 0])
        self.assertEqual(mask, [0.0] * 4 + [-65504.0] * 4 + [0.0, -65504.0, -65504.0])
        self.assertTrue(all(0 <= idx < 64 for idx in indices))

    def test_mask_half_precision_exact(self):
        self.assertEqual(struct.unpack('e', struct.pack('e', -65504.0))[0], -65504.0)

    def test_provenance_records_gather_flag(self):
        txt = BENCH_MODULE.read_text(encoding="utf-8")
        self.assertIn("QWEN4EXP_", txt)

    def test_plan_never_reuses_published_binary_or_unsafe_backend_suite(self):
        txt = PLAN.read_text(encoding="utf-8")
        self.assertIn("BuildKeys = @('R6RocmCommon005')", txt)
        self.assertNotIn("BuildKeys = @('CombinedROCm')", txt)
        self.assertIn("Mtp              = $false", txt)
        self.assertIn("KvType           = 'f16'", txt)
        self.assertIn("Name = 'common005-fallback-smoke'", txt)
        self.assertIn("Name = 'common005-activation-32k'", txt)
        self.assertIn("Name = 'common005-long-abba'", txt)
        self.assertIn("InputKey = '128k'", txt)
        self.assertIn("InputKey = '256k'", txt)
        self.assertIn("QWEN4EXP_QSA_GATHER = '1'", txt)
        self.assertIn("QWEN4EXP_QSA_GATHER = '0'", txt)
        self.assertNotIn("-RunBackendTest", txt)


if __name__ == "__main__":
    unittest.main()
