#!/usr/bin/env python3
"""Decode/visualize r6 Vulkan fa_mask_opt 2-bit tile snapshots (stdlib only).

The input is an already-computed *tile classification*, not raw attention logits
and not a promise that the GPU skipped every tile marked ALL_NEG_INF.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
from xml.sax.saxutils import escape

CODES = {0: "MIXED", 1: "ALL_NEG_INF", 2: "ALL_ZERO", 3: "INVALID"}
COLORS = {0: "#efb664", 1: "#365b82", 2: "#35a99c", 3: "#b84780"}
DIFF = {0: ("UNCHANGED", "#cbd2d8"),
        1: ("SKIP_LOST_A_TO_B", "#e66e45"),
        2: ("SKIP_GAINED_A_TO_B", "#148f83"),
        3: ("OTHER_CHANGE", "#7d56a1")}
META_FIELDS = ("kv", "n", "br", "bc", "words_per_row",
               "tiles_per_row", "rows", "slices", "payload_bytes")


def load_snapshot(prefix: str | Path) -> tuple[dict, list[list[list[int]]]]:
    prefix = Path(prefix)
    meta = json.loads(Path(str(prefix) + ".json").read_text(encoding="utf-8"))
    if meta.get("schema_version") != 1 or meta.get("word_encoding") != "uint32_le_16x2bit":
        raise ValueError("Unsupported snapshot schema / word encoding")
    for key in META_FIELDS:
        if type(meta.get(key)) is not int or meta[key] <= 0:
            raise ValueError(f"Invalid or missing positive metadata: {key}")
    rows, cols, planes = meta["rows"], meta["tiles_per_row"], meta["slices"]
    words = meta["words_per_row"]
    # mask_opt stride is allocated from mask.ne0, which can be padded beyond
    # the logical KV depth. Retain and skip unused padding words; do not
    # require the final word to contain a valid logical tile.
    if cols > words * 16:
        raise ValueError("Tile columns exceed available packed row stride")
    ne0 = meta.get("mask_ne0")
    if ne0 is not None:
        if type(ne0) is not int or ne0 <= 0 or words != math.ceil(ne0 / (16 * meta["bc"])):
            raise ValueError("Packed row stride disagrees with mask_ne0 / Bc")
    if rows * cols * planes > (1 << 20):
        raise ValueError("Unreasonably large logical tile map")
    expected = words * rows * planes * 4
    if expected > (1 << 20) or meta["payload_bytes"] != expected:
        raise ValueError("Binary size is inconsistent with row/plane dimensions")
    if math.ceil(meta["kv"] / meta["bc"]) != cols:
        raise ValueError("KV/Bc does not match the logical number of tile columns")
    payload = Path(str(prefix) + ".bin").read_bytes()
    if len(payload) != expected:
        raise ValueError(f"Binary length {len(payload)} differs from {expected}")
    integers = [w[0] for w in struct.iter_unpack("<I", payload)]
    result = []
    for z in range(planes):
        layer = []
        for row in range(rows):
            start = (z * rows + row) * words
            values = [(integers[start + j // 16] >> (2 * (j % 16))) & 3
                      for j in range(cols)]
            if 3 in values:
                raise ValueError(f"Reserved 2-bit code 3 at slice={z} row={row}")
            layer.append(values)
        result.append(layer)
    meta["payload_sha256"] = hashlib.sha256(payload).hexdigest()
    return meta, result


def counts(values: list[list[int]]) -> dict:
    d = {CODES[i]: sum(row.count(i) for row in values) for i in CODES}
    d["total"] = sum(map(len, values))
    d["skippable_fraction"] = d["ALL_NEG_INF"] / d["total"] if d["total"] else 0.0
    return d


def export_axis_csv(values: list[list[int]], prefix: Path) -> None:
    rows = len(values)
    cols = len(values[0])
    for axis in ("row", "column"):
        dest = Path(f"{prefix}-{axis}-summary.csv")
        with dest.open("w", encoding="utf-8", newline="") as file:
            writer = csv.writer(file)
            writer.writerow([axis, "all_neg_inf", "all_zero", "mixed", "invalid",
                             "total", "skippable_fraction", "max_contiguous_skip_run"])
            length = rows if axis == "row" else cols
            for i in range(length):
                seq = values[i] if axis == "row" else [values[y][i] for y in range(rows)]
                t = counts([seq])
                best = current = 0
                for v in seq:
                    current = current + 1 if v == 1 else 0
                    best = max(best, current)
                writer.writerow([i, t["ALL_NEG_INF"], t["ALL_ZERO"], t["MIXED"],
                                 t["INVALID"], t["total"], f'{t["skippable_fraction"]:.8f}', best])


def svg_heatmap(values: list[list[int]], title: str, colors: dict[int, str],
                labels: dict[int, str], path: Path) -> None:
    if not values or not values[0]:
        raise ValueError("Empty tile map")
    rows, cols = len(values), len(values[0])
    if any(len(row) != cols for row in values):
        raise ValueError("Ragged tile map")
    cw = max(2, min(16, int(1200 / cols)))
    ch = 8
    left, top = 48, 38
    width = left + cols * cw + 20
    height = top + rows * ch + 88
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#f7f9fb"/>',
        f'<text x="12" y="21" font-size="15" fill="#202a34">{escape(title)}</text>',
        f'<text x="8" y="{top + rows * ch // 2}" font-size="12" fill="#243140">Q</text>',
    ]
    # Horizontal run-length encoding keeps even a 64k (64x768) SVG compact.
    for y, row in enumerate(values):
        j = 0
        while j < cols:
            k = j + 1
            while k < cols and row[k] == row[j]:
                k += 1
            parts.append(f'<rect x="{left + j*cw}" y="{top + y*ch}" '
                         f'width="{(k-j)*cw}" height="{ch}" fill="{colors[row[j]]}"/>')
            j = k
    parts.append(f'<text x="{left}" y="{top + rows*ch + 23}" font-size="12" fill="#243140">'
                 f'KV tile (columns={cols}); Q tile rows={rows}</text>')
    xpos, ypos = left, top + rows * ch + 46
    for key, label in labels.items():
        parts.append(f'<rect x="{xpos}" y="{ypos-11}" width="12" height="12" fill="{colors[key]}"/>')
        parts.append(f'<text x="{xpos+17}" y="{ypos}" font-size="11" fill="#243140">{escape(label)}</text>')
        xpos += max(118, len(label) * 7 + 34)
    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def render(prefix: str, out: str, slice_index: int) -> dict:
    meta, planes = load_snapshot(prefix)
    if slice_index < 0 or slice_index >= len(planes):
        raise ValueError("Requested slice outside snapshot")
    rows = planes[slice_index]
    dest = Path(out)
    dest.parent.mkdir(parents=True, exist_ok=True)
    svg_heatmap(rows, f'{meta["query"]} KV={meta["kv"]} slice={slice_index}',
                COLORS, CODES, dest)
    stem = dest.with_suffix("")
    export_axis_csv(rows, stem)
    summary = {"source_prefix": str(prefix), "slice": slice_index, "metadata": meta,
               "counts": counts(rows)}
    Path(str(stem) + "-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def compare(a: str, b: str, out: str, slice_index: int) -> dict:
    ma, aa = load_snapshot(a)
    mb, bb = load_snapshot(b)
    for key in ("kv", "n", "br", "bc", "words_per_row", "tiles_per_row", "rows", "slices", "query"):
        if ma.get(key) != mb.get(key):
            raise ValueError(f"Cannot compare different capture geometry/query: {key}")
    if not 0 <= slice_index < ma["slices"]:
        raise ValueError("Requested slice outside snapshot")
    arows, brows = aa[slice_index], bb[slice_index]
    diff = []
    for ar, br in zip(arows, brows):
        diff.append([0 if x == y else 1 if x == 1 and y != 1
                     else 2 if x != 1 and y == 1 else 3
                     for x, y in zip(ar, br)])
    dst = Path(out)
    dst.parent.mkdir(parents=True, exist_ok=True)
    stem = dst.with_suffix("")
    svg_heatmap(arows, "A: " + ma["query"], COLORS, CODES, Path(str(stem) + "-A.svg"))
    svg_heatmap(brows, "B: " + mb["query"], COLORS, CODES, Path(str(stem) + "-B.svg"))
    svg_heatmap(diff, "B minus A, same tile coordinates", {k: val[1] for k, val in DIFF.items()},
                {k: val[0] for k, val in DIFF.items()}, dst)
    export_axis_csv(arows, Path(str(stem) + "-A"))
    export_axis_csv(brows, Path(str(stem) + "-B"))
    total = len(arows) * len(arows[0])
    summary = {
        "a_prefix": a, "b_prefix": b, "slice": slice_index,
        "geometry": {key: ma[key] for key in ("kv", "n", "br", "bc", "query", "rows", "tiles_per_row")},
        "a": counts(arows), "b": counts(brows),
        "unchanged": sum(row.count(0) for row in diff),
        "skip_lost": sum(row.count(1) for row in diff),
        "skip_gained": sum(row.count(2) for row in diff),
        "other_change": sum(row.count(3) for row in diff),
        "total_tiles": total,
    }
    summary["changed"] = total - summary["unchanged"]
    Path(str(stem) + "-comparison.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest="command", required=True)
    r = cmds.add_parser("render", help="Render an individual packed FA mask tile snapshot")
    r.add_argument("--prefix", required=True, help="Common prefix of .json and .bin files")
    r.add_argument("--out", required=True, help="Output SVG path")
    r.add_argument("--slice", type=int, default=0)
    c = cmds.add_parser("compare", help="Compare same geometry/query snapshots from two corpora")
    c.add_argument("--a", required=True, help="Capture A prefix")
    c.add_argument("--b", required=True, help="Capture B prefix")
    c.add_argument("--out", required=True, help="Difference SVG path; also writes A/B maps")
    c.add_argument("--slice", type=int, default=0)
    args = parser.parse_args()
    result = render(args.prefix, args.out, args.slice) if args.command == "render" \
        else compare(args.a, args.b, args.out, args.slice)
    print(json.dumps(result if args.command == "compare" else result["counts"], indent=2))


if __name__ == "__main__":
    main()
