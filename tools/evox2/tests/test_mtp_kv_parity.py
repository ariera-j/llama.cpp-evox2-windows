"""Synthetic regression tests for the diagnostic Draft KV state reader.

No actual model/GPU required. Native Windows build and real GGUF verification
remain separate mandatory gates.
"""
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "benchmark"))
from analyze_mtp_kv_parity import compare, mapped_file, parse_snapshot


def write_fake_state(path: Path, positions, *, ext=0, transposed=False,
                     v_change=0.0, seq_id=0):
    """Write a minimal seq-state file with one f16 attention KV layer."""
    out = bytearray(struct.pack("<III", 0x4C4C4D43, 1, 0))
    out += struct.pack("<II", 1, len(positions))
    for pos in positions:
        out += struct.pack("<iI", pos, 1)
        out += b"\x00" * ext
        out += struct.pack("<i", seq_id)
    out += struct.pack("<IIII", int(transposed), 1, 0, 0)
    out += struct.pack("<iQ", 1, 4)  # f16 K, two values per token
    for p in positions:
        out += struct.pack("<ee", float(p + 1), float(p + 2))
    if transposed:
        out += struct.pack("<iII", 1, 2, 2)
        for dim in range(2):
            for p in positions:
                out += struct.pack("<e", float(p + 3 + dim + v_change))
    else:
        out += struct.pack("<iQ", 1, 4)
        for p in positions:
            out += struct.pack("<ee", float(p + 3 + v_change), float(p + 4 + v_change))
    out += b"\xff\x00\x01\x02"  # recurrent section, intentionally not parsed
    path.write_bytes(out)


class TestMtpDraftKvParity(unittest.TestCase):
    def test_f16_equal_and_physical_slot_permutation(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "a.bin"
            b = Path(d) / "b.bin"
            write_fake_state(a, [0, 1, 2])
            write_fake_state(b, [2, 0, 1])
            result = compare(a, b)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["position_count"], 3)
            self.assertEqual([x["kind"] for x in result["layers"]], ["K", "V"])

    def test_detects_numeric_v_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "a.bin"
            b = Path(d) / "b.bin"
            write_fake_state(a, [0, 1, 2])
            write_fake_state(b, [0, 1, 2], v_change=0.25)
            result = compare(a, b)
            self.assertEqual(result["status"], "FAIL")
            self.assertTrue(result["layers"][0]["pass"])
            self.assertFalse(result["layers"][1]["pass"])

    def test_transposed_v_and_cell_ext(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "a.bin"
            b = Path(d) / "b.bin"
            write_fake_state(a, [0, 3, 5], ext=12, transposed=True)
            write_fake_state(b, [5, 0, 3], ext=12, transposed=True)
            result = compare(a, b)
            self.assertEqual(result["status"], "PASS")
            self.assertTrue(result["v_trans"])
            with mapped_file(a) as data:
                obj = parse_snapshot(data, str(a))
            self.assertEqual(obj.positions, (0, 3, 5))

    def test_fails_on_position_and_sequence_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "a.bin"
            b = Path(d) / "b.bin"
            write_fake_state(a, [0, 1, 2])
            write_fake_state(b, [0, 1, 3])
            with self.assertRaisesRegex(ValueError, "position mismatch"):
                compare(a, b)
            write_fake_state(b, [0, 1, 2], seq_id=1)
            with self.assertRaisesRegex(ValueError, "seq_id mapping mismatch"):
                compare(a, b)


if __name__ == "__main__":
    unittest.main()
