#!/usr/bin/env python3
"""Parse opt-in r5 MTP PP trace records from a *single* native stderr log.

Pure standard library. The trace records CPU-side wall intervals only:
draft llama_process need not mean GPU completion; hidden getter can synchronize.
Do not add inclusive parent/child durations as independent costs.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

MARKER = "mtp_pp_trace_v1 "
INT_FIELDS = (
    "calls", "tokens", "end_pos", "n_tokens", "total_us", "target_us",
    "target_sync_us", "spec_us", "hidden_get_us", "prepare_us",
    "draft_us", "verify_copy_us",
)
TIMINGS = (
    "total_us", "target_us", "target_sync_us", "spec_us", "hidden_get_us",
    "prepare_us", "draft_us", "verify_copy_us",
)
FIELDS = ("role", "phase", "kv_bin", "end_pos", "n_tokens", "calls", "tokens", *TIMINGS)
ROW_FIELDS = ("role", "phase", "kv_bin", "end_pos", "n_tokens", *TIMINGS,
              "draft_us_per_token", "total_us_per_token")


def depth_bin(end_pos: int) -> str:
    kv = end_pos + 1
    for maximum, label in ((32768, "0-32768"), (65536, "32769-65536"),
                           (131072, "65537-131072"), (262144, "131073-262144")):
        if kv <= maximum:
            return label
    return "262145+"


def parse_lines(lines: list[str]) -> tuple[list[dict], list[dict]]:
    bins: list[dict] = []
    rows: list[dict] = []
    for no, line in enumerate(lines, 1):
        offset = line.find(MARKER)
        if offset < 0:
            continue
        payload = line[offset + len(MARKER):].strip()
        fields: dict = {}
        for part in payload.split():
            if "=" not in part:
                raise ValueError(f"line {no}: malformed record {part!r}")
            key, value = part.split("=", 1)
            if key in fields:
                raise ValueError(f"line {no}: duplicate field {key!r}")
            fields[key] = int(value) if key in INT_FIELDS else value
        if fields.get("type") not in ("bin", "row"):
            raise ValueError(f"line {no}: unknown trace record type")
        for required in ("role", "phase", "total_us", "n_tokens" if fields["type"] == "row" else "calls"):
            if required not in fields:
                raise ValueError(f"line {no}: missing {required}")
        for key in TIMINGS:
            fields.setdefault(key, 0)
        if any(fields[key] < 0 for key in TIMINGS):
            raise ValueError(f"line {no}: negative timing interval")
        if fields["type"] == "row":
            if fields["n_tokens"] <= 0 or fields.get("end_pos", -1) < 0:
                raise ValueError(f"line {no}: invalid row tokens/position")
            fields["kv_bin"] = depth_bin(fields["end_pos"])
            fields["draft_us_per_token"] = round(fields["draft_us"] / fields["n_tokens"], 3)
            fields["total_us_per_token"] = round(fields["total_us"] / fields["n_tokens"], 3)
            rows.append(fields)
        else:
            bins.append(fields)
    return bins, rows


def validate(bins: list[dict], rows: list[dict]) -> None:
    if not bins:
        raise ValueError("no mtp_pp_trace_v1 bin records: verify source, mode, stderr and normal process exit")
    if not rows:
        return  # mode=bins intentionally has no detail rows
    for role, phase, kv_bin in sorted({(r["role"], r["phase"], r["kv_bin"]) for r in rows}):
        samples = [r for r in rows if (r["role"], r["phase"], r["kv_bin"]) == (role, phase, kv_bin)]
        matched = [b for b in bins if (b["role"], b["phase"], b["kv_bin"]) == (role, phase, kv_bin)]
        if len(matched) != 1:
            raise ValueError(f"duplicate/missing bin for {role}/{phase}/{kv_bin}")
        summary = matched[0]
        if len(samples) != summary["calls"] or sum(r["n_tokens"] for r in samples) != summary["tokens"]:
            raise ValueError(f"incomplete detail rows for {role}/{phase}/{kv_bin}")
        for key in TIMINGS:
            if sum(r[key] for r in samples) != summary[key]:
                raise ValueError(f"timing mismatch for {role}/{phase}/{kv_bin}/{key}")


def csv_write(path: Path, records: list[dict], columns: tuple[str, ...]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for record in records:
            writer.writerow(record)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log", type=Path, required=True, help="one run's native stderr.log")
    ap.add_argument("--outdir", type=Path, required=True)
    ap.add_argument("--require-prompt-draft", action="store_true",
                    help="fail if the traced run did not reach prompt MTP catch-up")
    ap.add_argument("--require-detail", action="store_true",
                    help="fail if the mode was bins instead of detail")
    args = ap.parse_args(argv)

    try:
        with args.log.open("r", encoding="utf-8", errors="replace") as f:
            bins, rows = parse_lines(f.readlines())
        validate(bins, rows)
        if args.require_prompt_draft and not any(
                b["role"] == "draft" and b["phase"] == "prompt" for b in bins):
            raise ValueError("no prompt draft records: confirm MTP ON and selected sidecar")
        if args.require_detail and not rows:
            raise ValueError("no per-ubatch records: set LLAMA_MTP_PP_TRACE=detail")
        args.outdir.mkdir(parents=True, exist_ok=True)
        csv_write(args.outdir / "mtp-pp-bins.csv", bins, FIELDS)
        if rows:
            csv_write(args.outdir / "mtp-pp-rows.csv", rows, ROW_FIELDS)
        result = {
            "schema": "mtp_pp_trace_v1",
            "source_log": str(args.log),
            "bin_count": len(bins), "row_count": len(rows),
            "trace_mode": "detail" if rows else "bins",
            "bins": bins,
            "warnings": [
                "target_sync_us is a subset of target_us; spec_us encloses draft stage timings",
                "hidden_get_us may include queued GPU completion, not pure host-copy time",
                "draft_us is CPU wall around llama_process; GPU may still be queued",
                "parent/child durations are not additive and trace-enabled runs are not speed baselines",
                "server prompt timer may exclude work after the final prompt timestamp",
            ],
        }
        (args.outdir / "mtp-pp-summary.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError) as e:
        print(f"mtp-pp parser: {e}", file=sys.stderr)
        return 2
    print(f"trace parsed: {len(bins)} bins, {len(rows)} detailed rows -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
