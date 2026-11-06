"""Pure-Python synthetic Indexer diagnostic tests and source/plan contracts."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/evox2/benchmark/analyze_indexer_diag.py"
spec = importlib.util.spec_from_file_location("indexer_diag", SCRIPT)
diag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diag)


def fixture(prefix):
    prefix = str(prefix)
    n_pool, n_real, kpool, nq, ntop = 6, 4, 2, 4, 2
    meta = {
        "schema_version": 1, "kv": 8, "layer": 19, "q_global_first": 0,
        "n_tokens": 8, "q_local_start": 0, "q_global_start": 0,
        "q_count": nq, "n_pool": n_pool, "n_top_pool": ntop,
        "score_bytes": nq*n_pool*4, "topk_bytes": nq*ntop*4,
    }
    host = {k: meta[k] for k in
            ("kv", "n_tokens", "q_global_first", "q_local_start", "q_count", "n_pool")}
    host.update(schema_version=1, layer_target=19, kpool=kpool, n_pool_real=n_real)
    Path(prefix + "-meta.json").write_text(json.dumps(meta), encoding="utf-8")
    Path(prefix + "-pool-map.json").write_text(json.dumps(host), encoding="utf-8")
    lines = ["pool,member,seq_id,cache_cell,key_pos,real"]
    for pool in range(n_pool):
        for member in range(kpool):
            real = pool < n_real
            key = pool*kpool + member if real else -1
            lines.append(f"{pool},{member},{0 if real else -1},{key if real else 8},{key},{int(real)}")
    Path(prefix + "-pool-map.csv").write_text("\n".join(lines)+"\n", encoding="utf-8")
    scores = [4, 3, 1, 0, float("-inf"), float("-inf"),
              2, 2, 1, 0, float("-inf"), float("-inf"),
              0, 0, 0, 0, float("-inf"), float("-inf"),
              5, float("-inf"), float("-inf"), float("-inf"), float("-inf"), float("-inf")]
    topk = [1, 0, 1, 0, 1, 2, 0, 4]  # unordered, a tie, and an underfilled padded slot
    Path(prefix + "-score.f32").write_bytes(struct.pack("<24f", *scores))
    Path(prefix + "-topk.i32").write_bytes(struct.pack("<8i", *topk))


class ScoreTests(unittest.TestCase):
    def test_rank_ties_and_underfilled(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp)/"sample")
            fixture(prefix)
            meta, host, pools, scores, topk = diag.load_rows(prefix)
            summary, query, group, selected = diag.analyze(
                meta, host, pools, scores, topk, focus=(0, 2, 4))
            self.assertEqual(summary["focus_groups"]["0"], 3)
            self.assertEqual(query[0]["cutoff"], 3)
            self.assertEqual(query[3]["cutoff"], None)
            self.assertEqual(selected[3], {0})
            ties = [r for r in group if r["q_global"] == 1 and r["key_start"] == 0]
            self.assertEqual((ties[0]["rank_best"], ties[0]["rank_worst"]), (1, 2))
            out = str(Path(tmp)/"report")
            self.assertEqual(diag.inspect(prefix, out, (0,2,4))["query_rows"], 4)
            with self.assertRaises(FileExistsError):
                diag.inspect(prefix, out, (0,2,4))

    def test_bad_topk_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp)/"sample")
            fixture(prefix)
            buf = bytearray(Path(prefix+"-topk.i32").read_bytes())
            struct.pack_into("<2i", buf, 0, 0, 0)
            Path(prefix+"-topk.i32").write_bytes(buf)
            meta, host, pools, scores, topk = diag.load_rows(prefix)
            with self.assertRaisesRegex(ValueError, "duplicated"):
                diag.analyze(meta, host, pools, scores, topk)

    def test_f16_element_crosscheck(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp)/"sample")
            fixture(prefix)
            meta, host, pools, scores, topk = diag.load_rows(prefix)
            _, _, _, selected = diag.analyze(meta, host, pools, scores, topk)
            # Use a separate synthetic historical crop earlier than Query 100.
            meta["q_global_start"] = 100
            rawpre = str(Path(tmp)/"f16")
            rawmeta = {"kv": meta["kv"], "q_global_start": 100,
                       "k_global_start": 0, "rows": 4, "columns": 8}
            # For synthetic tests the Key range is close to the Query only
            # in token coordinates; qglobal is set far beyond the crop.
            Path(rawpre+"-raw.json").write_text(json.dumps(rawmeta), encoding="utf-8")
            values = []
            for q in range(4):
                chosen = {m["key"] for p in selected[q] for m in pools[p] if m["real"]}
                values += [0.0 if k in chosen else float("-inf") for k in range(8)]
            Path(rawpre+"-raw.bin").write_bytes(struct.pack("<32e", *values))
            self.assertEqual(diag.check_mask_crop(rawpre, meta, pools, selected), 32)
            values[0] = 0.0 if values[0] == float("-inf") else float("-inf")
            Path(rawpre+"-raw.bin").write_bytes(struct.pack("<32e", *values))
            with self.assertRaisesRegex(ValueError, "F16 mask mismatch"):
                diag.check_mask_crop(rawpre, meta, pools, selected)

    def test_src_is_bounded_opt_in(self):
        vk = (ROOT/"ggml/src/ggml-vulkan/ggml-vulkan.cpp").read_text(encoding="utf-8")
        types = (ROOT/"ggml/src/ggml-vulkan/ggml-vulkan-types.h").read_text(encoding="utf-8")
        graph = (ROOT/"src/models/qwen4exp.cpp").read_text(encoding="utf-8")
        host = (ROOT/"src/llama-memory-hybrid-idx.cpp").read_text(encoding="utf-8")
        self.assertIn("GGML_VK_INDEXER_DIAG", vk)
        self.assertIn("bytes > (16u << 20)", vk)
        self.assertIn("ggml_vk_indexer_diag_flush(ctx)", vk)
        self.assertIn("ggml_vk_buffer_copy_async(subctx, snapshot", vk)
        self.assertIn("vk_buffer indexer_diag_score_snapshot;", types)
        self.assertIn("evxidx-score-l%d-k%u-q%d-n%u", graph)
        self.assertIn("indexer_diag_saved.compare_exchange_strong", host)
        self.assertIn("pool,member,seq_id,cache_cell,key_pos,real", host)
        for p in (
            ROOT/"tools/evox2/benchmark/configs/qwen38-r6-indexer-score-1024-smoke-20261106.psd1",
            ROOT/"tools/evox2/benchmark/configs/qwen38-r6-indexer-score-64k-20261106.psd1",
        ):
            data = p.read_text(encoding="utf-8")
            self.assertIn("GGML_VK_INDEXER_DIAG", data)
            self.assertIn("UBatch           = 1024", data)
            self.assertIn("NoWarmup         = $true", data)


if __name__ == "__main__":
    unittest.main()
