"""Synthetic F16 raw-mask unit test and bounded source-contract checks."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / "tools/evox2/benchmark/visualize_fa_mask_raw.py"
CPP = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
TYPES = ROOT / "ggml/src/ggml-vulkan/ggml-vulkan-types.h"
PLAN = ROOT / "tools/evox2/benchmark/configs/qwen38-r6-fa-mask-raw-4x4-64k-20261106.psd1"
spec = importlib.util.spec_from_file_location("rawcrop", PY)
rawcrop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rawcrop)


def write_fixture(prefix, wrong=False):
    br, bc = 2, 4
    nr, nc = br * 4, bc * 4
    raw = [[float("-inf") for _ in range(nc)] for _ in range(nr)]
    raw[0][0] = 0.0     # first 2x4 tile becomes MIXED
    raw[0][4] = 0.0     # second tile MIXED
    raw[1][4] = 0.0
    for r in range(2, 4):
        for c in range(8, 12):
            raw[r][c] = 0.0  # ALL_ZERO
    meta = {
        "schema_version": 1, "encoding": "ieee754_float16_le",
        "query": "Qcur-19 (view) (permuted)", "kv": 128, "n": 64,
        "br": br, "bc": bc, "q_tile_start": 0, "k_tile_start": 20,
        "q_local_start": 0, "q_global_start": 64, "k_global_start": 80,
        "rows": nr, "columns": nc, "payload_bytes": nr*nc*2,
    }
    prefix = str(prefix)
    Path(prefix+"-raw.json").write_text(json.dumps(meta), encoding="utf-8")
    Path(prefix+"-raw.bin").write_bytes(struct.pack("<"+"e"*(nr*nc), *sum(raw, [])))
    # 4 tiles/row; first 20 columns and remaining 12 in each row arbitrary.
    words_per_row = 2
    packed = [[1]*32 for _ in range(4)]
    for tr in range(4):
        for tc in range(4):
            block = [row[tc*bc:(tc+1)*bc] for row in raw[tr*br:(tr+1)*br]]
            packed[tr][20+tc] = rawcrop.classify(block)
    dwords = []
    for row in packed:
        for i in range(0, 32, 16):
            dwords.append(sum(v << (2*k) for k,v in enumerate(row[i:i+16])))
    if wrong:
        dwords[1] ^= (1 << (2*4))
    Path(prefix+".bin").write_bytes(struct.pack("<"+"I"*len(dwords), *dwords))
    Path(prefix+".json").write_text(json.dumps({
        "schema_version": 1, "word_encoding": "uint32_le_16x2bit",
        "kv": 128, "n": 64, "br": br, "bc": bc,
        "query": meta["query"], "rows": 4, "tiles_per_row": 32,
        "words_per_row": 2, "payload_bytes": len(dwords)*4,
    }), encoding="utf-8")


class RawMaskContractTests(unittest.TestCase):
    def test_raw_image_and_2bit_consistency(self):
        with tempfile.TemporaryDirectory() as temp:
            pre = str(Path(temp)/"sample")
            write_fixture(pre)
            out = Path(temp)/"raw.svg"
            data = rawcrop.inspect(pre, str(out))
            self.assertEqual(data["packed_2bit_crosscheck"], "PASS")
            self.assertEqual(data["tile_count"], 16)
            self.assertTrue(out.exists())
            self.assertEqual(data["tile_details"][0]["packed_code"], 0)
            self.assertEqual(data["tile_details"][2]["packed_code"], 1)

    def test_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            pre = str(Path(temp)/"sample")
            write_fixture(pre, wrong=True)
            with self.assertRaisesRegex(ValueError, "classification mismatch"):
                rawcrop.inspect(pre, str(Path(temp)/"raw.svg"))

    def test_cpp_is_opt_in_bounded_and_deferred(self):
        src = CPP.read_text(encoding="utf-8")
        types = TYPES.read_text(encoding="utf-8")
        for label in ("std::getenv(\"GGML_VK_FA_MASK_DIAG_RAW\")",
                      "bytes_raw <= (1u << 16)",
                      "height <= 64 && width <= 256",
                      "mask->type == GGML_TYPE_F16",
                      "mask->nb[0] == sizeof(ggml_fp16_t)",
                      "ggml_vk_buffer_copy_async(subctx, ctx->fa_mask_diag_raw_snapshot",
                      "ggml_vk_fa_mask_diag_raw_flush(ctx);",
                      "ggml_vk_destroy_buffer(ctx->fa_mask_diag_raw_snapshot);"):
            self.assertIn(label, src)
        self.assertIn("vk_buffer fa_mask_diag_raw_snapshot;", types)

    def test_short_smoke_is_isolated_and_contains_causal_boundary(self):
        smoke_path = (ROOT / "tools/evox2/benchmark/configs/"
                      "qwen38-r6-fa-mask-raw-1024-smoke-20261106.psd1")
        smoke = smoke_path.read_text(encoding="utf-8")
        for term in (
            "PromptTokens     = @(1024)",
            "GenerationTokens = @(0)",
            "Context          = 2048",
            "UBatch           = 1024",
            "NoWarmup         = $true",
            "GGML_VK_FA_MASK_DIAG_KV         = '1024'",
            "GGML_VK_FA_MASK_DIAG_QUERY      = 'Qcur-19'",
            "GGML_VK_FA_MASK_DIAG_RAW       = '1'",
            "GGML_VK_FA_MASK_DIAG_RAW_Q_TILE = '32'",
            "GGML_VK_FA_MASK_DIAG_RAW_K_TILE = '8'",
            "Name = 'raw-mask-smoke-1024'",
            "GGML_VK_FA_RGP_MARKERS            = $null",
            "GGML_VK_FA_DISPATCH_TRACE         = $null",
        ):
            self.assertIn(term, smoke)
        self.assertEqual(smoke.count("Tool = 'bench'"), 1)
        self.assertEqual(smoke.count("GGML_VK_FA_MASK_DIAG_RAW       = '1'"), 1)

    def test_plan_two_separate_runs(self):
        data = PLAN.read_text(encoding="utf-8")
        self.assertEqual(data.count("Tool = 'bench'"), 2)
        self.assertEqual(data.count("GGML_VK_FA_MASK_DIAG_RAW       = '1'"), 2)
        self.assertIn("PromptTokens     = @(61777)", data)
        self.assertIn("Context          = 65536", data)
        self.assertIn("GGML_VK_FA_RGP_MARKERS            = $null", data)
        self.assertIn("GGML_VK_FA_DISPATCH_TRACE         = $null", data)
        self.assertIn("raw-mask-code", data)
        self.assertIn("raw-mask-literature", data)


if __name__ == "__main__":
    unittest.main()
