#!/usr/bin/env python3
"""Analyze original F32 Lightning Indexer scores and unordered I32 top-k pool IDs.

Pure Python stdlib. The scored pool is not an Attention weight. Always map
pool indices to logical Key positions using the captured host pool map.
"""
from __future__ import annotations

import argparse
from bisect import bisect_left, bisect_right
import csv
import json
import math
from pathlib import Path
import struct


DEFAULT_FOCUS = (1816, 2624, 5960, 5964, 5968, 5980, 5984, 6004,
                 30084, 30088, 30092, 30096, 30104, 30244)


def load_snapshot(prefix: str):
    base = str(prefix)
    meta = json.loads(Path(base + "-meta.json").read_text(encoding="utf-8"))
    host = json.loads(Path(base + "-pool-map.json").read_text(encoding="utf-8"))
    if meta.get("schema_version") != 1 or host.get("schema_version") != 1:
        raise ValueError("unknown score/top-k or pool-map schema")
    for field in ("kv", "n_tokens", "q_global_first", "q_local_start", "q_count", "n_pool"):
        if type(meta.get(field)) is not int or meta[field] < 0 or host.get(field) != meta[field]:
            raise ValueError(f"host/GPU mismatch: {field}")
    if type(meta.get("layer")) is not int or host.get("layer_target") != meta["layer"]:
        raise ValueError("host/GPU layer mismatch")
    n_pool = meta["n_pool"]
    n_top = meta.get("n_top_pool")
    count = meta["q_count"]
    kpool = host.get("kpool")
    if (type(n_top) is not int or type(kpool) is not int or
            not (0 < n_top <= n_pool <= 1048576) or not (0 < count <= 256) or
            not (1 < kpool <= 256) or meta["q_local_start"] + count > meta["n_tokens"]):
        raise ValueError("invalid score/top-k dimensions")
    if meta.get("q_global_start") != meta["q_global_first"] + meta["q_local_start"]:
        raise ValueError("Query base mismatch")
    if type(host.get("n_pool_real")) is not int or not 0 <= host["n_pool_real"] <= n_pool:
        raise ValueError("invalid real pool count")

    score_data = Path(base + "-score.f32").read_bytes()
    topk_data = Path(base + "-topk.i32").read_bytes()
    if (len(score_data) != count * n_pool * 4 or len(topk_data) != count * n_top * 4 or
            meta.get("score_bytes") != len(score_data) or meta.get("topk_bytes") != len(topk_data)):
        raise ValueError("truncated or unexpected GPU payload")

    pools = [[] for _ in range(n_pool)]
    with Path(base + "-pool-map.csv").open(newline="", encoding="utf-8") as f:
        for record in csv.DictReader(f):
            pool = int(record["pool"])
            member = int(record["member"])
            if pool < 0 or pool >= n_pool or member != len(pools[pool]):
                raise ValueError("pool map row ordering/index out of range")
            pools[pool].append({
                "key": int(record["key_pos"]),
                "cell": int(record["cache_cell"]),
                "seq": int(record["seq_id"]),
                "real": int(record["real"]),
            })
    if any(len(entries) != kpool for entries in pools):
        raise ValueError("pool member count mismatch")
    for i, members in enumerate(pools):
        real = i < host["n_pool_real"]
        if any(bool(m["real"]) != real for m in members):
            raise ValueError("incorrect real/padded flag")
        if real and (any(m["key"] < 0 or m["cell"] < 0 for m in members) or
                     len({m["key"] for m in members}) != kpool):
            raise ValueError("invalid real pool key mapping")
        if not real and any(m["key"] != -1 for m in members):
            raise ValueError("invalid padded pool")

    return (meta, host, pools, score_data, topk_data)


def load_rows(prefix: str):
    meta, host, pools, raw_scores, raw_topk = load_snapshot(prefix)
    n, k, count = meta["n_pool"], meta["n_top_pool"], meta["q_count"]
    scores = [struct.unpack_from(f"<{n}f", raw_scores, q*n*4) for q in range(count)]
    topk = [struct.unpack_from(f"<{k}i", raw_topk, q*k*4) for q in range(count)]
    return meta, host, pools, scores, topk


def analyze(meta, host, pools, scores, topk, focus=DEFAULT_FOCUS):
    n_pool, n_top = meta["n_pool"], meta["n_top_pool"]
    if len(scores) != meta["q_count"] or len(topk) != meta["q_count"]:
        raise ValueError("Query row count mismatch")
    start_to_pool = {}
    for p in range(host["n_pool_real"]):
        keys = sorted(m["key"] for m in pools[p])
        start = keys[0]
        if start in start_to_pool:
            raise ValueError(f"ambiguous Key group start: {start}")
        start_to_pool[start] = p

    focus = list(dict.fromkeys(int(x) for x in focus))
    query_rows = []
    group_rows = []
    selected_per_q = []
    for qi, (score, ids) in enumerate(zip(scores, topk)):
        if len(score) != n_pool or len(ids) != n_top:
            raise ValueError("score/top-k row shape mismatch")
        if any(math.isnan(v) for v in score):
            raise ValueError(f"NaN score at Query row {qi}")
        if any(p < 0 or p >= n_pool for p in ids) or len(set(ids)) != len(ids):
            raise ValueError(f"bad or duplicated TOP_K indices at Query row {qi}")
        valid = [p for p, s in enumerate(score) if math.isfinite(s)]
        if any(p >= host["n_pool_real"] for p in valid):
            raise ValueError("padded pool received a finite score")
        if any(score[p] < 0 for p in valid):
            raise ValueError("unexpected negative rectified score")
        selected = {p for p in ids if math.isfinite(score[p])}
        expected_count = min(len(valid), n_top)
        if len(selected) != expected_count:
            raise ValueError(f"unexpected live TOP_K count at Query row {qi}")
        cutoff = min((score[p] for p in selected), default=None) if len(valid) >= n_top else None
        if cutoff is not None and any(score[p] > cutoff for p in valid if p not in selected):
            raise ValueError("TOP_K excludes a strictly higher-scoring pool")
        ascending = sorted(score[p] for p in valid)
        qglobal = meta["q_global_start"] + qi
        selected_per_q.append(selected)
        query_rows.append({
            "q_global": qglobal, "n_valid": len(valid), "n_top_pool": n_top,
            "n_selected_live": len(selected), "cutoff": cutoff,
            "selected_pool_ids": " ".join(str(p) for p in sorted(selected)),
        })
        for key_start in focus:
            p = start_to_pool.get(key_start)
            if p is None:
                continue
            value = score[p]
            finite = math.isfinite(value)
            if finite:
                rank_best = len(valid) - bisect_right(ascending, value) + 1
                rank_worst = len(valid) - bisect_left(ascending, value)
            else:
                rank_best = rank_worst = None
            group_rows.append({
                "q_global": qglobal, "key_start": key_start, "pool": p,
                "visible": finite, "selected": p in selected,
                "score": value if finite else None,
                "rank_best": rank_best, "rank_worst": rank_worst,
                "cutoff": cutoff, "margin": value - cutoff if finite and cutoff is not None else None,
            })
    summary = {
        "schema": "evox2_indexer_analysis_v1", "query_rows": len(query_rows),
        "n_pool": n_pool, "n_top_pool": n_top, "kpool": host["kpool"],
        "q_global_start": meta["q_global_start"], "layer": meta["layer"], "kv": meta["kv"],
        "focus_groups": {str(k): sum(r["selected"] for r in group_rows if r["key_start"] == k)
                         for k in focus if k in start_to_pool},
    }
    return summary, query_rows, group_rows, selected_per_q


def check_mask_crop(prefix: str, meta, pools, selected_per_q):
    """Crosscheck a previous 64x256 original F16 mask, excluding tail cells.

    Valid for historical crops fully earlier than all sampled Queries. Returns
    the number of individual F16 positions whose actual selection matches.
    """
    rawmeta = json.loads(Path(prefix + "-raw.json").read_text(encoding="utf-8"))
    if rawmeta.get("kv") != meta["kv"]:
        raise ValueError("F16 crop KV mismatch")
    rows, cols = rawmeta["rows"], rawmeta["columns"]
    q_start = rawmeta["q_global_start"]
    k_start = rawmeta["k_global_start"]
    if (q_start < meta["q_global_start"] or
            q_start + rows > meta["q_global_start"] + meta["q_count"] or
            k_start + cols >= q_start - 4 or rows <= 0 or cols <= 0):
        raise ValueError("F16 crop outside scored Query rows or too close to incomplete tail")
    data = Path(prefix + "-raw.bin").read_bytes()
    if len(data) != rows * cols * 2:
        raise ValueError("bad F16 payload size")
    checked = 0
    for y in range(rows):
        qi = q_start - meta["q_global_start"] + y
        selected_keys = {entry["key"] for pool in selected_per_q[qi]
                         for entry in pools[pool] if entry["real"]}
        for x in range(cols):
            expected = (k_start + x) in selected_keys
            actual = struct.unpack_from("<e", data, 2*(y*cols+x))[0]
            if actual != (0.0 if expected else -math.inf):
                raise ValueError(f"F16 mask mismatch: Q={q_start+y} K={k_start+x}")
            checked += 1
    return checked


def inspect(prefix: str, out: str, focus=DEFAULT_FOCUS, raw_prefixes=()):
    meta, host, pools, scores, topk = load_rows(prefix)
    summary, qrows, grows, selected = analyze(meta, host, pools, scores, topk, focus)
    summary["mask_crosschecks"] = {
        key: check_mask_crop(key, meta, pools, selected) for key in raw_prefixes
    }
    outpath = Path(out)
    outpath.parent.mkdir(parents=True, exist_ok=True)
    paths = [outpath.with_name(outpath.name + suffix) for suffix in
             ("-summary.json", "-query.csv", "-group.csv")]
    if any(p.exists() for p in paths):
        raise FileExistsError("refusing to overwrite earlier analysis")
    paths[0].write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    for path, rows in zip(paths[1:], (qrows, grows)):
        with path.open("w", newline="", encoding="utf-8") as f:
            if rows:
                writer = csv.DictWriter(f, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--prefix", required=True, help="GPU diagnostic file prefix")
    ap.add_argument("--out", required=True, help="prefix for derived summary/CSV")
    ap.add_argument("--focus", default=",".join(map(str, DEFAULT_FOCUS)))
    ap.add_argument("--raw-prefix", action="append", default=[],
                    help="previous F16 crop prefix; repeat for multiple windows")
    args = ap.parse_args()
    focus = [int(x) for x in args.focus.split(",") if x.strip()]
    print(json.dumps(inspect(args.prefix, args.out, focus, args.raw_prefix),
                     indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
