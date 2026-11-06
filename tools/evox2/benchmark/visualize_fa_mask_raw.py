#!/usr/bin/env python3
"""Inspect a bounded original F16 FA mask crop and check against 2-bit tile codes.

Standalone Python stdlib; no GPU required for decoding. Existing 2-bit
classification is a uniformity test, NOT the fraction of unmasked tokens.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import struct
from xml.sax.saxutils import escape


def load_crop(prefix: str):
    rawpath = Path(prefix + "-raw.bin")
    m = json.loads(Path(prefix + "-raw.json").read_text(encoding="utf-8"))
    if m.get("schema_version") != 1 or m.get("encoding") != "ieee754_float16_le":
        raise ValueError("unsupported F16 crop format")
    for field in ("kv", "n", "br", "bc", "q_tile_start", "k_tile_start",
                  "q_local_start", "k_global_start", "rows", "columns", "payload_bytes"):
        if type(m.get(field)) is not int or m[field] < 0:
            raise ValueError(f"missing/invalid non-negative field: {field}")
    nr, nc = m["rows"], m["columns"]
    if not 1 <= nr <= 64 or not 1 <= nc <= 256 or nr * nc * 2 != m["payload_bytes"]:
        raise ValueError("bad dimensions / payload_bytes")
    if nr != 4 * m["br"] or nc != 4 * m["bc"]:
        raise ValueError("expected exactly 4x4 raw mask tiles")
    if m["q_local_start"] != m["q_tile_start"] * m["br"]:
        raise ValueError("q local index mismatch")
    if m["k_global_start"] != m["k_tile_start"] * m["bc"]:
        raise ValueError("k global index mismatch")
    if m.get("q_global_start") != m["kv"] - m["n"] + m["q_local_start"]:
        raise ValueError("q global index mismatch")
    if m["q_local_start"] + nr > m["n"] or m["k_global_start"] + nc > m["kv"]:
        raise ValueError("crop outside mask tensor")
    data = rawpath.read_bytes()
    if len(data) != m["payload_bytes"]:
        raise ValueError("raw binary size mismatch")
    values = [v[0] for v in struct.iter_unpack("<e", data)]
    if any(math.isnan(x) for x in values):
        raise ValueError("NaN encountered in raw F16 mask")
    return m, [values[y * nc:(y + 1) * nc] for y in range(nr)]


def classify(values):
    """Shader equivalent for finite f16 / ±infinity values."""
    flat = [v for row in values for v in row]
    if all(v == -math.inf for v in flat):
        return 1
    if all(v == 0.0 for v in flat):
        return 2
    return 0


def vclass(x: float):
    if x == -math.inf:
        return 1
    if x == 0.0:
        return 2
    return 0


def check_original_tile_codes(prefix: str, m: dict, raw) -> list[dict]:
    packed = json.loads(Path(prefix + ".json").read_text(encoding="utf-8"))
    if packed["schema_version"] != 1 or packed["word_encoding"] != "uint32_le_16x2bit":
        raise ValueError("unsupported 2-bit reference")
    for field in ("kv", "n", "br", "bc", "query"):
        if packed[field] != m[field]:
            raise ValueError(f"2-bit geometry or query differs: {field}")
    if m["q_tile_start"] + 4 > packed["rows"] or m["k_tile_start"] + 4 > packed["tiles_per_row"]:
        raise ValueError("tile area exceeds 2-bit reference")
    packed_data = Path(prefix + ".bin").read_bytes()
    if len(packed_data) != packed["payload_bytes"]:
        raise ValueError("truncated 2-bit reference")
    words = [x[0] for x in struct.iter_unpack("<I", packed_data)]
    stride = packed["words_per_row"]
    br, bc = m["br"], m["bc"]
    results = []
    for tr in range(4):
        for tc in range(4):
            row_id, col_id = m["q_tile_start"] + tr, m["k_tile_start"] + tc
            word = words[row_id * stride + col_id // 16]
            expected_code = (word >> (2 * (col_id % 16))) & 3
            block = [row[tc * bc:(tc + 1) * bc]
                     for row in raw[tr * br:(tr + 1) * br]]
            actual_code = classify(block)
            cnt = Counter(vclass(x) for row in block for x in row)
            if actual_code != expected_code:
                raise ValueError(f"mask tile classification mismatch at {row_id},{col_id}: "
                                 f"packed={expected_code} raw={actual_code}")
            results.append({
                "q_tile": row_id, "k_tile": col_id,
                "q_tokens": [m["q_global_start"] + tr * br,
                             m["q_global_start"] + (tr + 1) * br],
                "k_tokens": [m["k_global_start"] + tc * bc,
                             m["k_global_start"] + (tc + 1) * bc],
                "packed_code": expected_code,
                "blocked_neg_inf": cnt[1],
                "allowed_zero": cnt[2],
                "other_finite_or_pos_inf": cnt[0],
                "total": br * bc,
                "unblocked_fraction": round((cnt[2] + cnt[0]) / (br * bc), 6),
            })
    return results


def write_svg(path: Path, m: dict, raw):
    colors = {0: "#e7a85a", 1: "#365b82", 2: "#2baf9f"}
    nr, nc = len(raw), len(raw[0])
    left, top, cw, ch = 54, 54, 4, 6
    w, h = left + nc * cw + 30, top + nr * ch + 85
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
        '<rect width="100%" height="100%" fill="#f9fbfc"/>',
        f'<text x="12" y="23" font-size="15" fill="#17212b">'
        f'{escape(m["query"])} Q={m["q_global_start"]}.. '
        f'KV={m["k_global_start"]}..</text>',
    ]
    for y, row in enumerate(raw):
        classes = [vclass(x) for x in row]
        j = 0
        while j < nc:
            k = j + 1
            while k < nc and classes[j] == classes[k]:
                k += 1
            lines.append(f'<rect x="{left + j*cw}" y="{top + y*ch}" '
                         f'width="{(k-j)*cw}" height="{ch}" fill="{colors[classes[j]]}"/>')
            j = k
    for x in range(5):
        xpos = left + x * m["bc"] * cw
        lines.append(f'<line x1="{xpos}" y1="{top}" x2="{xpos}" y2="{top+nr*ch}" stroke="#111827" stroke-opacity=".45"/>')
    for y in range(5):
        ypos = top + y * m["br"] * ch
        lines.append(f'<line x1="{left}" y1="{ypos}" x2="{left+nc*cw}" y2="{ypos}" stroke="#111827" stroke-opacity=".45"/>')
    base = top + nr * ch + 26
    for x, (v, name) in enumerate([(1, "blocked -inf"), (2, "allowed zero"), (0, "other finite/inf")]):
        xx = left + x * 170
        lines.append(f'<rect x="{xx}" y="{base-13}" width="12" height="12" fill="{colors[v]}"/>')
        lines.append(f'<text x="{xx+18}" y="{base}" font-size="12">{name}</text>')
    lines.append('</svg>')
    path.write_text("\n".join(lines), encoding="utf-8")


def inspect(prefix: str, out: str):
    m, raw = load_crop(prefix)
    tiles = check_original_tile_codes(prefix, m, raw)
    counts = Counter(vclass(x) for row in raw for x in row)
    total = m["rows"] * m["columns"]
    summary = {
        "schema": "evox2_fa_mask_raw_inspection_v1",
        "prefix": prefix,
        "metadata": m,
        "tile_count": len(tiles),
        "packed_2bit_crosscheck": "PASS",
        "blocked_neg_inf": counts[1],
        "allowed_zero": counts[2],
        "other_finite_or_pos_inf": counts[0],
        "unblocked_fraction": round((counts[2]+counts[0]) / total, 7),
        "tile_details": tiles
    }
    dest = Path(out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    write_svg(dest, m, raw)
    dest.with_suffix(".json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True,
                        help="prefix of .bin/.json and -raw.bin/-raw.json")
    parser.add_argument("--out", required=True, help="output zoom SVG")
    args = parser.parse_args()
    result = inspect(args.prefix, args.out)
    print(json.dumps({k:v for k,v in result.items() if k not in ("tile_details", "metadata")},
                     indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
