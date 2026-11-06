"""Synthetic, CPU-only tests of 2-bit fa_mask_opt visualization."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/evox2/benchmark/visualize_fa_mask_tiles.py"
spec = importlib.util.spec_from_file_location("evox2_mask_vis", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture(prefix: Path, planes, *, kv=192, bc=64, query="Qcur-19 (view) (permuted)"):
    rows, cols = len(planes[0]), len(planes[0][0])
    words = (cols + 15) // 16
    packed = []
    for layer in planes:
        for row in layer:
            assert len(row) == cols
            for chunk in range(words):
                word = sum(v << (2 * (i % 16))
                           for i, v in enumerate(row[chunk*16:(chunk+1)*16], chunk*16))
                packed.append(word)
    payload = struct.pack("<" + "I" * len(packed), *packed)
    prefix = str(prefix)
    meta = {"schema_version": 1, "word_encoding": "uint32_le_16x2bit", "source": "test",
            "query": query, "kv": kv, "n": rows*16, "br": 16, "bc": bc,
            "n_kv_max": kv, "words_per_row": words, "tiles_per_row": cols,
            "rows": rows, "slices": len(planes), "payload_bytes": len(payload)}
    Path(prefix + ".json").write_text(json.dumps(meta), encoding="utf-8")
    Path(prefix + ".bin").write_bytes(payload)


class FaMaskTilesTests(unittest.TestCase):
    def test_exact_positions_and_slice(self):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp) / "sample"
            fixture(prefix, [[[0, 1, 2], [1, 1, 0]], [[2, 0, 1], [0, 0, 1]]])
            meta, planes = module.load_snapshot(prefix)
            self.assertEqual(meta["rows"], 2)
            self.assertEqual(planes[0], [[0, 1, 2], [1, 1, 0]])
            self.assertEqual(planes[1], [[2, 0, 1], [0, 0, 1]])
            out = Path(tmp) / "image.svg"
            summary = module.render(str(prefix), str(out), 0)
            self.assertEqual(summary["counts"]["ALL_NEG_INF"], 3)
            self.assertIn("<svg", out.read_text(encoding="utf-8"))
            self.assertTrue((Path(tmp) / "image-row-summary.csv").exists())
            self.assertTrue((Path(tmp) / "image-column-summary.csv").exists())

    def test_difference_and_geometry_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp)/"a", Path(tmp)/"b"
            fixture(a, [[[1, 0, 2]]])
            fixture(b, [[[0, 1, 2]]])
            d = module.compare(str(a), str(b), str(Path(tmp)/"diff.svg"), 0)
            self.assertEqual((d["skip_lost"], d["skip_gained"], d["changed"]), (1, 1, 2))
            self.assertTrue((Path(tmp)/"diff-A.svg").exists())
            self.assertTrue((Path(tmp)/"diff-B.svg").exists())
            fixture(b, [[[0, 1, 2]]], kv=384)
            with self.assertRaises(ValueError):
                module.compare(str(a), str(b), str(Path(tmp)/"bad.svg"), 0)

    def test_binary_length_and_reserved_value_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = Path(tmp)/"a"
            fixture(a, [[[0, 1, 2]]])
            f = Path(str(a) + ".bin")
            f.write_bytes(b"\0")
            with self.assertRaisesRegex(ValueError, "Binary length"):
                module.load_snapshot(a)
            fixture(a, [[[3, 1, 2]]])
            with self.assertRaisesRegex(ValueError, "Reserved"):
                module.load_snapshot(a)

    def test_padding_across_16_word_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = Path(tmp)/"a"
            row = [0]*16 + [1, 2]
            fixture(a, [[row]], kv=18*64)
            m, p = module.load_snapshot(a)
            self.assertEqual(m["words_per_row"], 2)
            self.assertEqual(p[0][0][16:], [1, 2])


if __name__ == "__main__":
    unittest.main()
