#!/usr/bin/env python3
"""Summarize opt-in HIP Dense MUL_MAT dispatch messages from llama-cli stderr."""

import argparse
from collections import Counter
from pathlib import Path

MARKER = "evox2_dense_gemm_v1 "
KEYS = ("layer", "weight", "weight_type", "path", "compute_type", "K", "M", "N")


def parse_records(lines):
    records = []
    truncated = False
    for line in lines:
        position = line.find(MARKER)
        if position < 0:
            continue
        data = {}
        for token in line[position + len(MARKER):].split():
            if "=" in token:
                key, value = token.split("=", 1)
                data[key] = value
        if "truncated_after" in data:
            truncated = True
            continue
        if all(key in data for key in KEYS):
            try:
                for key in ("seq", "device", "layer", "K", "M", "N", "w2", "w3", "a2", "a3"):
                    if key in data:
                        data[key] = int(data[key])
            except ValueError:
                continue
            records.append(data)
    return records, truncated


def aggregate(records):
    return Counter(
        (row["layer"], row["weight"], row["weight_type"], row["path"],
         row["compute_type"], row["K"], row["M"], row["N"])
        for row in records
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", type=Path, help="llama-cli stderr log")
    ap.add_argument("--layer", type=int, help="restrict to this layer")
    ap.add_argument("--n", type=int, help="restrict to this matrix N")
    ap.add_argument("--strict", action="store_true", help="fail for truncated or missing matching records")
    args = ap.parse_args(argv)

    with args.log.open(encoding="utf-8", errors="replace") as f:
        rows, truncated = parse_records(f)
    selected = [
        row for row in rows
        if (args.layer is None or row["layer"] == args.layer)
        and (args.n is None or row["N"] == args.n)
    ]
    print(f"Dense dispatch records: {len(selected)} selected / {len(rows)} total; truncated={truncated}")
    print("count layer path       weight_type compute_type K      M      N      weight")
    for key, count in sorted(aggregate(selected).items(), key=lambda item: (
            item[0][0], item[0][1], item[0][3], item[0][5:])):
        layer, weight, weight_type, path, compute_type, k, m, n = key
        print(f"{count:5d} {layer:5d} {path:10s} {weight_type:11s} {compute_type:12s} "
              f"{k:6d} {m:6d} {n:6d} {weight}")
    if truncated:
        print("WARNING: trace hit GGML_HIP_GEMM_TRACE_LIMIT; counts may be incomplete")
    if args.strict and (truncated or not selected):
        ap.error("trace truncated or no matching records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
