"""Static check for the isolated ROCm RGP anchor gate."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FA = ROOT / "ggml/src/ggml-cuda/fattn.cu"
MMQ = ROOT / "ggml/src/ggml-cuda/mmq.cu"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-rocm-moe-rgp-anchor-20261107.psd1"


class HipRgpAnchorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fa = FA.read_text(encoding="utf-8")
        cls.mmq = MMQ.read_text(encoding="utf-8")
        cls.plan = PLAN.read_text(encoding="utf-8")

    def test_opt_in_and_hip_gate(self):
        for src in (self.fa, self.mmq):
            self.assertIn('std::getenv("GGML_HIP_RGP_ANCHOR")', src)
            self.assertIn('std::strcmp(env, "1") == 0', src)
            self.assertIn('#if defined(GGML_USE_HIP)', src)
            self.assertIn('asm volatile("s_nop 0")', src)

    def test_fa_anchor_placement_and_kv(self):
        body = self.fa.split("void ggml_cuda_flash_attn_ext(ggml_backend_cuda_context", 1)[1]
        self.assertIn("evox2_hip_anchor_fa_layer19<<<128, 64, 0, ctx.stream()>>>();", body)
        self.assertIn("evox2_hip_anchor_fa_layer23<<<128, 64, 0, ctx.stream()>>>();", body)
        self.assertIn("(filter_kv < 0 || k->ne[1] == filter_kv)", body)
        self.assertLess(body.index("evox2_hip_anchor_fa_layer19<<<"), body.index("switch (kernel)"))

    def test_moe_anchor_placement_and_metadata(self):
        body = self.mmq.split("const bool dedup_bcast = ne11 == 1 && n_expert_used > 1;", 1)[1]
        self.assertIn("evox2_hip_anchor_moe_layer19<<<128, 64, 0, stream>>>();", body)
        self.assertIn("evox2_hip_anchor_moe_layer23<<<128, 64, 0, stream>>>();", body)
        self.assertIn("J_best, ggml_type_name(src0->type)", body)
        self.assertIn("KV=unknown", body)
        self.assertLess(body.index("evox2_hip_anchor_moe_layer19<<<"), body.index("ggml_cuda_launch_mm_ids_helper("))

    def test_moe_visibility_probe_covers_all_gate_layers(self):
        src = self.mmq
        self.assertIn('std::getenv("GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE")', src)
        self.assertIn('std::strstr(src0->name, "ffn_gate_exps.weight")', src)
        self.assertIn('evox2_hip_anchor_moe_any_gate<<<128, 64, 0, stream>>>();', src)
        self.assertIn('evox2_hip_anchor_probe_v1', src)
        self.assertIn('moe-anchor-code-visibility-probe-64k', self.plan)

    def test_no_new_gpu_synchronization(self):
        for src, marker in (
                (self.fa, "static __global__ void evox2_hip_anchor_fa_layer19"),
                (self.mmq, "static __global__ void evox2_hip_anchor_moe_layer19")):
            probe = src.split(marker, 1)[1]
            for forbidden in ("hipDeviceSynchronize(", "cudaDeviceSynchronize(", "cudaStreamSynchronize("):
                self.assertNotIn(forbidden, probe)

    def test_plan_disables_topk_callback(self):
        self.assertIn("GGML_EVOX2_MOE_TOPK_TRACE         = $null", self.plan)
        self.assertIn("GGML_HIP_RGP_ANCHOR               = '1'", self.plan)
        self.assertIn("GGML_HIP_RGP_ANCHOR_KV            = '49152'", self.plan)
        self.assertIn("R6RocmMoeAnchorProbe", self.plan)


if __name__ == "__main__":
    unittest.main()
