#!/usr/bin/env python3
"""Summarize ROCM-002 final regression runs (64k, 128k, 256k, Gemma 4 32k) into summary.csv."""

import argparse
import csv
import json
import os
import re
import statistics
from datetime import datetime

GIB = 1024.0 ** 3


def fval(x):
    if x is None or x == "" or str(x).lower() == "nan":
        return None
    try:
        return float(x)
    except Exception:
        return None


def parse_iso(ts):
    if not ts:
        return None
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    m = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d+)([+-]\d{2}:\d{2})?$", ts)
    if m:
        frac = (m.group(2) + "000000")[:6]
        tz = m.group(3) or "+00:00"
        ts = f"{m.group(1)}.{frac}{tz}"
    return datetime.fromisoformat(ts).timestamp()


def parse_stderr_ts(line):
    m = re.match(r"^(\d+)\.(\d{2})\.(\d{3})\.(\d{3})\s", line)
    if not m:
        return None
    return int(m.group(1)) * 60 + int(m.group(2)) + int(m.group(3)) / 1000.0 + int(m.group(4)) / 1000000.0


def summarize_run(label, rdir):
    with open(os.path.join(rdir, "result.json"), "r", encoding="utf-8-sig") as f:
        rj = json.load(f)
    with open(os.path.join(rdir, "ram-detail.csv"), "r", encoding="utf-8-sig") as f:
        ram_rows = list(csv.DictReader(f))
    with open(os.path.join(rdir, "resources.csv"), "r", encoding="utf-8-sig") as f:
        res_rows = list(csv.DictReader(f))
    with open(os.path.join(rdir, "gpu-metrics.csv"), "r", encoding="utf-8-sig") as f:
        adlx_rows = list(csv.DictReader(f))
    with open(os.path.join(rdir, "stderr.log"), "r", encoding="utf-8-sig", errors="replace") as f:
        stderr_lines = f.readlines()

    ram_avail = [fval(r.get("AvailableRAMBytes")) / GIB for r in ram_rows if fval(r.get("AvailableRAMBytes")) is not None]
    ram_commit = [fval(r.get("CommitTotalBytes")) / GIB for r in ram_rows if fval(r.get("CommitTotalBytes")) is not None]
    ram_limit = [fval(r.get("CommitLimitBytes")) / GIB for r in ram_rows if fval(r.get("CommitLimitBytes")) is not None]

    wddm_ad_ded = [fval(r.get("AdapterDedicated_GiB")) for r in res_rows if fval(r.get("AdapterDedicated_GiB")) is not None]
    wddm_ad_shd = [fval(r.get("AdapterShared_GiB")) for r in res_rows if fval(r.get("AdapterShared_GiB")) is not None]
    wddm_pid_ded = [fval(r.get("TargetGPUDedicated_GiB")) for r in res_rows if fval(r.get("TargetGPUDedicated_GiB")) is not None]
    pages_in = [fval(r.get("PagesInput_PerSec")) for r in res_rows if fval(r.get("PagesInput_PerSec")) is not None]
    disk_read = [fval(r.get("DiskRead_MiBps")) for r in res_rows if fval(r.get("DiskRead_MiBps")) is not None]
    adlx_vram = [fval(r.get("gpu_vram_mb")) for r in adlx_rows if fval(r.get("gpu_vram_mb")) is not None]

    t_load_start, t_ctx_start = None, None
    for l in stderr_lines:
        if "load_tensors: loading model tensors" in l and t_load_start is None:
            t_load_start = parse_stderr_ts(l)
        if "llama_context: constructing llama_context" in l and t_ctx_start is None:
            t_ctx_start = parse_stderr_ts(l)

    return {
        "Label": label,
        "RunId": rj.get("RunId"),
        "Status": rj.get("Status"),
        "ExitCode": rj.get("ExitCode"),
        "RequestedContext": rj.get("RequestedContext"),
        "ActualContext": rj.get("ActualContext"),
        "PromptTokens": rj.get("PromptTokens"),
        "GeneratedTokens": rj.get("GeneratedTokens"),
        "PP_tok_s": rj.get("PromptTokensPerSecond"),
        "TG_tok_s": rj.get("GenerationTokensPerSecond"),
        "PP_ms": rj.get("PromptEvalMilliseconds"),
        "TG_ms": rj.get("GenerationEvalMilliseconds"),
        "DurationSeconds": rj.get("DurationSeconds"),
        "LoadToCtxSec": round(t_ctx_start - t_load_start, 3) if (t_load_start is not None and t_ctx_start is not None) else None,
        "MinAvailRAM_GiB": round(min(ram_avail), 3) if ram_avail else None,
        "Under1GiB_Samples": sum(1 for x in ram_avail if x < 1.0),
        "CommitPeak_GiB": round(max(ram_commit), 3) if ram_commit else None,
        "CommitLimit_GiB": round(max(ram_limit), 3) if ram_limit else None,
        "WddmAdapterDedPeak_GiB": round(max(wddm_ad_ded), 3) if wddm_ad_ded else None,
        "WddmAdapterShdPeak_GiB": round(max(wddm_ad_shd), 3) if wddm_ad_shd else None,
        "WddmPidDedPeak_GiB": round(max(wddm_pid_ded), 3) if wddm_pid_ded else None,
        "AdlxVramPeak_MB": max(adlx_vram) if adlx_vram else None,
        "PagesInputPeak_PerSec": round(max(pages_in), 1) if pages_in else None,
        "DiskReadPeak_MiBps": round(max(disk_read), 2) if disk_read else None,
        "PModeStart": (rj.get("PModeAtStart") or {}).get("Mode"),
        "PModeFinish": (rj.get("PModeAtFinish") or {}).get("Mode"),
        "OutputFingerprintSha256": rj.get("OutputFingerprintSha256"),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_csv")
    parser.add_argument("--run", action="append", nargs=2, metavar=("LABEL", "DIR"), required=True)
    args = parser.parse_args()

    rows = [summarize_run(label, rdir) for label, rdir in args.run]
    with open(args.output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
