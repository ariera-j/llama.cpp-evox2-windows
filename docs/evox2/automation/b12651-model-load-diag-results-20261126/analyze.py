"""Verify b12690 diagnostics and summarize the preserved Matrix runs."""
import argparse
from bisect import bisect_right
import csv
from datetime import datetime
from decimal import Decimal
import hashlib
from html import escape
import json
from pathlib import Path
import re
from statistics import mean, median

PREFIX = "llama_load_diag "
BIN_US = [100, 1000, 5000, 10000, 20000, 50000, 100000, 500000, 1000000]
GIB = 1 << 30
MIB = 1 << 20
SUM_KEYS = ("calls", "bytes", "sum_us", "max_us")
GROUP_EVENTS = ("group_begin", "group_phase", "progress", "group_end")
RUN_EVENTS = ("load_tensors_begin", "mappings_begin", "mappings_end", "buffers_ready",
              "postprocess_begin", "load_tensors_end")
EXPECTED_SHA = "aad7b53f5e67fb83e493611bae9818096efa8b3159748a9ef7c482aa78e1187d"
EXPECTED_SOURCE = "d32cdfaf1c86739b6479260e6324d1394081cf50"
TENSOR_TABLE = Path(__file__).resolve().parents[2] / "pr30904-preport-20261125" / "tensors.csv"


def require(condition, description):
    if not condition:
        raise ValueError(description)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def seconds(value):
    # Windows timestamps may have seven fractional digits. Preserve all digits.
    m = re.fullmatch(r"(.*T\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)", value)
    require(m is not None, f"Invalid timestamp: {value}")
    base, fraction, offset = m.groups()
    zone = "+00:00" if offset == "Z" else offset
    return Decimal(int(datetime.fromisoformat(base + zone).timestamp())) + Decimal(fraction or "0")


def round_value(value):
    return round(value, 6) if isinstance(value, (float, Decimal)) else value


def write_csv(path, rows):
    if not rows:
        return
    names = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=names, lineterminator="\n")
        writer.writeheader()
        writer.writerows({k: round_value(v) for k, v in row.items()} for row in rows)


def counters(record, operation):
    return record["operations"].get(operation, {})


def count_bytes(record, names):
    return sum(counters(record, name).get("bytes", 0) for name in names)


def cpu_us(record, names):
    return sum(counters(record, name).get("sum_us", 0) for name in names)


def position_ok(pos):
    nonnegative = ("tensor", "file_offset", "tensor_file_offset", "tensor_offset", "request_bytes")
    return all(type(pos[k]) is int and pos[k] >= 0 for k in nonnegative) and all(
        type(pos[k]) is int and pos[k] >= -1 for k in ("shard", "slot"))


def verify_diagnostics(lines, mode):
    found = []
    count_bytes_stderr = 0
    for index, line in enumerate(lines, 1):
        if "llama_load_diag" in line:
            require(line.startswith(PREFIX), f"Malformed diagnostic prefix at stderr line {index}")
            record = json.loads(line.removeprefix(PREFIX))
            record["stderr_line"] = index
            found.append(record)
            count_bytes_stderr += len(line.encode("utf-8")) + 2
    if mode == "OFF":
        require(not found, "Unexpected diagnostic line in OFF run")
        return found, count_bytes_stderr
    require(found, "Missing diagnostic records in ON run")
    require(all(x["schema"] == 1 for x in found), "Unexpected diagnostic schema")
    require([x["event"] for x in found if "group" not in x] == list(RUN_EVENTS), "Absent or unordered model markers")
    require(all(b["load_elapsed_us"] >= a["load_elapsed_us"] for a, b in zip(found, found[1:])), "Nonmonotonic load clock")
    group = 0
    previous = None
    started = None
    ended = 0
    for r in found:
        if "group" not in r:
            continue
        event = r["event"]
        require(event in GROUP_EVENTS, f"Unexpected group event: {event}")
        if event == "group_begin":
            require(ended == group and r["group"] == group + 1, "Nonsequential group number")
            group = r["group"]
            previous = None
            started = r["load_elapsed_us"]
        require(r["group"] == group and ended < group, "Group outside begin/end")
        require(r["wall_us"] == r["load_elapsed_us"] - started, "Invalid group wall time")
        ops = r["operations"]
        require(r["classified_us"] == sum(x["sum_us"] for x in ops.values()), "Classified time differs from sum")
        require(r["wall_us"] == r["classified_us"] + r["unclassified_us"] and r["unclassified_us"] >= 0,
                "Invalid wall/classified/unclassified relation")
        require(r["read_requested_bytes"] == count_bytes(r, ("read", "host_read")), "Read request bytes mismatch")
        require(r["transfer_logical_bytes"] == count_bytes(r, ("upload", "sync_set", "mapped_set")), "Logical transfer bytes mismatch")
        require(position_ok(r["active"]), "Invalid active position")
        if previous:
            for k in ("completed_tensors", "read_requested_bytes", "transfer_logical_bytes"):
                require(r[k] >= previous[k], f"Nonmonotonic {k}")
            require(r["buffer_type"] == previous["buffer_type"], "Buffer type changed within group")
            for operation, stats in previous["operations"].items():
                require(all(ops[operation][k] >= stats[k] for k in SUM_KEYS), f"Nonmonotonic {operation}")
        for operation, stats in ops.items():
            require(all(type(stats[k]) is int and stats[k] >= 0 for k in (*SUM_KEYS, "interval_max_us")),
                    f"Invalid counters for {operation}")
            require(stats["calls"] > 0 and stats["interval_max_us"] <= stats["max_us"] <= stats["sum_us"],
                    f"Invalid timing for {operation}")
            if event == "group_end":
                hist = stats["histogram"]
                require(len(hist) == len(BIN_US) + 1 and all(type(v) is int and v >= 0 for v in hist)
                        and sum(hist) == stats["calls"], f"Invalid {operation} histogram")
                max_bin = bisect_right(BIN_US, stats["max_us"])
                require(hist[max_bin] and not any(hist[max_bin + 1:]), f"Max outside {operation} histogram")
        if event == "group_end":
            waits = r["long_waits"]
            expected_waits = min(8, sum(sum(x["histogram"][7:]) for x in ops.values()))
            require(r["status"] == "ok" and len(waits) == expected_waits, "Bad group status or wait count")
            require(all(a["duration_us"] >= b["duration_us"] for a, b in zip(waits, waits[1:])),
                    "Unsorted waits")
            for w in waits:
                require(position_ok(w["position"]) and started <= w["start_us"]
                        and w["start_us"] + w["duration_us"] <= r["load_elapsed_us"]
                        and 100000 <= w["duration_us"] <= ops[w["op"]]["max_us"], "Invalid long wait")
            ended = group
        previous = r
    require(group > 0 and ended == group, "Incomplete group records")
    for end in (x for x in found if x["event"] == "group_end"):
        phases = [x["route"] for x in found if x.get("group") == end["group"] and x["event"] == "group_phase"]
        expected_tail = ["drain", "finalize"] if counters(end, "drain") else ["finalize"]
        require(phases and phases[0] in ("async_ready", "async_unavailable")
                and phases[1:] == expected_tail, "Expected group phases are missing")
    require(any(x["event"] == "progress" and x["group"] == 1 for x in found), "Missing progress in GPU group")
    return found, count_bytes_stderr


def summarize(root, controller, rows, tensors):
    run = controller["Run"]
    run_id, mode = run["MatrixRunId"], controller["Mode"]
    d = root / run["ChildRunId"]
    status = load_json(d / "result.json")
    conditions = load_json(d / "conditions.json")
    matrix_dir = controller["Batch"].rsplit("\\", 1)[-1]
    matrix = load_json(root / "matrix" / matrix_dir / "matrix-result.json")
    require(matrix["Complete"] and not matrix["StoppedEarly"] and matrix["RunCountFinished"] == 1
            and matrix["Runs"][0]["MatrixRunId"] == run_id and matrix["Runs"][0]["ChildRunId"] == d.name
            and all(not check["Issue"] for check in matrix["SafetyChecks"]), "Matrix result or gates failed")
    require(controller["DiagRestored"] and status["ExitCode"] == 0 and status["Status"] == run["MatrixStatus"] == "OK",
            "Controller or child status failed")
    for gate in (controller["Before"], controller["Gate"]):
        require(gate["PMode"] == "Performance" and not gate["Processes"]
                and all(not gate[channel]["Serious"] for channel in ("System", "Application")),
                "Unexpected P-MODE, residual process or safety event")
    require(run["GpuRecovery"] == run["RamDetailSystemRecovery"] == "WithinTolerance", "Recovery check failed")
    require(status["PModeAtStart"]["Mode"] == status["PModeAtFinish"]["Mode"] == "Performance"
            and not status["PModeChanged"], "P-MODE changed during child run")
    require(status["ExecutableSha256"] == EXPECTED_SHA and status["BuildNumber"] == 12690, "Incorrect artifact")
    manifest = conditions["BuildManifest"]
    require(manifest["BuildIdentity"]["Status"] == "Verified" and manifest["BuildSource"]["Commit"] == EXPECTED_SOURCE,
            "Build manifest source or verification mismatch")
    env = conditions["Environment"]
    require(env.get("LLAMA_MODEL_LOAD_DIAG") == ("1" if mode == "ON" else None), "Incorrect child flag")
    require(all(not k.startswith(("GGML_VK_", "LLAMA_MTP", "LLAMA_EVOX2_RGP")) for k in env),
            "Unexpected experimental flag")
    effective = conditions["EffectiveCondition"]
    bench = effective["Benchmark"]
    expected_params = dict(PromptTokens=[8192], GenerationTokens=[256], Depths=[0], Repetitions=1,
                           DelaySeconds=0, KvType="f16", UBatch=1024, Batch=2048, Threads=4, GpuLayers=999,
                           CpuMoe=0, FlashAttn="on", NoWarmup=False, ExtraArgs=["--device", "Vulkan0", "--progress", "--verbose"])
    require(all(bench[k] == value for k, value in expected_params.items())
            and effective["Backend"] == "Vulkan" and effective["Device"]["Id"] == "Vulkan0"
            and effective["ManualConditions"]["UmaLabel"] == "UMA96GB"
            and effective["Model"]["LengthBytes"] == 81961816672
            and effective["Model"]["Path"].endswith("-ple16.gguf"),
            "Effective workload differs")
    require(conditions["ResourceMonitor"]["IntervalSeconds"] == 2
            and conditions["AdlxGpuMonitor"]["IntervalMs"] == 2000
            and conditions["RamDetail"]["Settings"]["IntervalMs"] == 250, "Monitoring intervals differ")
    native = load_json(d / "llama-bench.json")
    require(len(native) == 2 and [(x["n_prompt"], x["n_gen"], x["n_depth"]) for x in native] ==
            [(8192, 0, 0), (0, 256, 0)], "Native JSON shape changed")
    require(all(x["build_number"] == 12690 and x["build_commit"].startswith("d32cdfaf1") and
                len(x["samples_ns"]) == 1 and x["avg_ts"] > 0 for x in native), "Native data mismatch")
    require(controller["PP"] == native[0]["avg_ts"] and controller["TG"] == native[1]["avg_ts"], "Native/Matrix speed mismatch")
    raw = (d / "stderr.log").read_bytes()
    lines = raw.decode("utf-8-sig", errors="replace").splitlines()
    trace = [json.loads(line) for line in (d / "ram-events.jsonl").read_text(encoding="utf-8-sig").splitlines()]
    start = seconds(status["TargetLifecycle"]["StartedUtc"])
    target = next(x["Data"] for x in trace if x["Event"] == "TargetPidObserved")
    require(seconds(target["StartUtc"]) == start and all(x["RunId"] == d.name for x in trace), "PID, start or run mismatch")
    ram_monitor = load_json(d / "ram-monitor.json")
    require(ram_monitor["RunId"] == d.name and ram_monitor["TargetId"] == target["Id"]
            and seconds(ram_monitor["TargetStartUtc"]) == start, "RAM monitor PID or start mismatch")
    markers = [x for x in trace if x["Event"] == "LogMarkerReceived" and x["Data"]["Stream"] == "stderr"]

    def mark(phase):
        return next(x for x in markers if x["Data"]["Phase"] == phase)

    capacity = [x for x in markers if x["Data"]["Phase"] == "TensorLoadOrPlacement"
                and "model buffer size" in lines[x["Data"]["Line"] - 1]][-1]
    context = mark("ContextInitialization")
    warm = mark("WarmupReported")
    cap_s, context_s, warm_s = [float(seconds(x["TimestampUtc"]) - start) for x in (capacity, context, warm)]
    prompt_s = float(seconds(mark("PromptRunReported")["TimestampUtc"]) - start)
    reserve_ms = float(next(m[1] for line in lines if (m := re.search(r"reserve took +([0-9.]+) ms", line))))
    diagnostics, diag_bytes = verify_diagnostics(lines, mode)
    ram = load_csv(d / "ram-detail.csv")
    res = load_csv(d / "resources.csv")
    gpu = load_csv(d / "gpu-metrics.csv")
    require(ram and res and gpu and all(x["RunId"] == d.name for x in ram + res), "Missing or incorrect monitor rows")
    require(all(x["NativeStatus"] == "Complete" for x in ram), "Incomplete detail RAM")
    require(all(int(b["StopwatchTicks"]) > int(a["StopwatchTicks"]) for a, b in zip(ram, ram[1:])),
            "RAM stopwatch ordering failed")
    for samples, pid_key, start_key in ((ram, "TargetPID", "TargetStartUtc"), (res, "TargetPID", "TargetProcessStart")):
        for x in samples:
            if x[pid_key]:
                require(int(x[pid_key]) == target["Id"] and seconds(x[start_key]) == start, "Monitoring PID/start mismatch")

    def attach_time(samples, name, zone=""):
        for x in samples:
            x["relative_s"] = float(seconds(x[name] + zone) - start)

    attach_time(ram, "TimestampUtc")
    attach_time(res, "TimestampUtc")
    attach_time(gpu, "timestamp_local", "+09:00")
    runtime = status["TargetLifecycle"]["ProcessSeconds"]
    during = [x for x in ram if 0 <= x["relative_s"] <= runtime]
    peak = max(during, key=lambda x: int(x["UsedRAMBytes"]))
    core = dict(run=run_id, mode=mode)
    for filename in ("result.json", "conditions.json", "llama-bench.json", "stderr.log", "ram-events.jsonl",
                     "ram-detail.csv", "ram-monitor.json", "resources.csv", "gpu-metrics.csv"):
        path = d / filename
        data = raw if filename == "stderr.log" else path.read_bytes()
        rows["input_hashes"].append(dict(core, path=path.relative_to(root).as_posix(), bytes=len(data),
                                         sha256=hashlib.sha256(data).hexdigest()))
    summary = dict(core, child=d.name, matrix=matrix_dir, pid=target["Id"], start_utc=target["StartUtc"],
                   exit_utc=status["TargetLifecycle"]["ExitedUtc"],
                   boot_utc=controller["OsStartup"]["LastBootUpTimeUtc"], uptime_h=controller["OsStartup"]["UptimeHours"],
                   cache_before_gib=controller["Before"]["SystemCacheGiB"],
                   cap_s=cap_s, context_s=context_s, cap_to_context_s=context_s-cap_s, context_to_warmup_s=warm_s-context_s,
                   warmup_to_pp_s=prompt_s-warm_s, pp_reserve_ms=reserve_ms,
                   native_load_s=controller["NativeLoad"], process_s=runtime, wrapper_s=run["WrapperSeconds"],
                   pp=controller["PP"], tg=controller["TG"], ram_min_gib=min(int(x["AvailableRAMBytes"]) for x in during)/GIB,
                   commit_max_gib=max(int(x["CommitTotalBytes"]) for x in during)/GIB,
                   ws_max_gib=max(int(x["WorkingSetBytes"]) for x in during if x["WorkingSetBytes"])/GIB,
                   private_max_gib=max(int(x["PrivateBytes"]) for x in during if x["PrivateBytes"])/GIB,
                   ram_peak_s=peak["relative_s"], ram_peak_to_context_s=context_s-peak["relative_s"],
                   ram_peak_cache_gib=int(peak["SystemCacheBytes"])/GIB,
                   ram_peak_ws_gib=int(peak["WorkingSetBytes"])/GIB if peak["WorkingSetBytes"] else None,
                   ram_peak_private_gib=int(peak["PrivateBytes"])/GIB if peak["PrivateBytes"] else None,
                   ram_peak_commit_gib=int(peak["CommitTotalBytes"])/GIB,
                   ram_interval_mean_ms=mean(float(x["IntervalMsActual"]) for x in ram if x["IntervalMsActual"]),
                   ram_n=len(ram), resource_n=len(res), adlx_n=len(gpu), stderr_bytes=len(raw), diag_records=len(diagnostics),
                   diag_bytes_including_crlf=diag_bytes, stderr_sha256=hashlib.sha256(raw).hexdigest())
    for k in ("DiskRead_MiBps", "PagesInput_PerSec", "CPU_Percent", "TargetGPUDedicated_GiB", "TargetGPUShared_GiB"):
        for tag, lo, hi in (("bulk", 7, 45), ("late", context_s-14, context_s)):
            vals = [float(x[k]) for x in res if lo <= x["relative_s"] < hi and x[k]]
            summary[f"{tag}_{k}"] = median(vals) if vals else None
    for tag, phase, sample in zip(("pp", "tg"), ("PromptRunReported", "GenerationRunReported"), native):
        t = float(seconds(mark(phase)["TimestampUtc"]) - start)
        span = sample["samples_ns"][0] / 1e9
        hi = [x for x in gpu if t <= x["relative_s"] <= t + span and float(x["gpu_usage_pct"]) >= 90]
        summary[f"{tag}_adlx_n"] = len(hi)
        for name in ("gpu_clock_mhz", "gpu_vram_clock_mhz"):
            summary[f"{tag}_{name}"] = mean(float(x[name]) for x in hi) if hi else None
    for x in res:
        rows["resources"].append(dict(core, process_s=x["relative_s"],
            native_memory_s=float(seconds(x["NativeMemoryTimestampUtc"])-start) if x["NativeMemoryTimestampUtc"] else None,
            process_memory_s=float(seconds(x["ProcessMemoryTimestampUtc"])-start) if x["ProcessMemoryTimestampUtc"] else None,
            **{k: x[k] for k in ("DiskRead_MiBps", "DiskWrite_MiBps", "PagesInput_PerSec", "PageFaults_PerSec",
                "PageReads_PerSec", "CPU_Percent", "SystemCache_GiB", "TargetWS_GiB", "TargetPrivate_GiB",
                "TargetGPUDedicated_GiB", "TargetGPUShared_GiB", "TargetGPUEngineSum_Percent", "PerfMonPidGpuStatus")}))
    for x in gpu:
        rows["adlx"].append(dict(core, process_s=x["relative_s"],
            **{k: x[k] for k in ("gpu_usage_pct", "gpu_vram_mb", "gpu_clock_mhz", "gpu_vram_clock_mhz")}))
    last_second = None
    for x in ram:
        t = x["relative_s"]
        second = int(t // 1)
        if second != last_second or min(abs(t-peak["relative_s"]), abs(t-context_s)) <= 2:
            values = {key: int(x[key])/GIB if x[key] else None for key in
                ("AvailableRAMBytes", "CommitTotalBytes", "SystemCacheBytes", "WorkingSetBytes", "PrivateBytes")}
            rows["ram_selected"].append(dict(core, process_s=t,
                **{k.removesuffix("Bytes")+"_GiB": v for k, v in values.items()}))
        last_second = second
    rows["runs"].append(summary)
    if not diagnostics:
        return
    anchor = next(x["load_elapsed_us"] for x in diagnostics if x["event"] == "buffers_ready")

    def aligned(model_us):
        return cap_s + (model_us-anchor)/1e6

    model_end = next(x["load_elapsed_us"] for x in diagnostics if x["event"] == "load_tensors_end")
    summary["capacity_anchor_end_minus_context_s"] = aligned(model_end) - context_s
    group_ends = [r for r in diagnostics if r["event"] == "group_end"]
    require([(r["buffer_type"], r["completed_tensors"]) for r in group_ends] ==
            [("Vulkan0", 1238), ("Vulkan_Host", 1)], "Model data groups differ")
    def tensor_name(position):
        # Resolve by shard and GGUF absolute tensor offset. Group ordinals follow load order.
        return tensors.get(position["tensor_file_offset"]) if position["shard"] == 0 else None

    last = None
    for r in diagnostics:
        event = r["event"]
        identifier = dict(core, group=r.get("group"), buffer=r.get("buffer_type"))
        rows["boundaries"].append(dict(identifier, event=event, route=r.get("route"), model_us=r["load_elapsed_us"],
                                       estimated_process_s=aligned(r["load_elapsed_us"]), stderr_line=r["stderr_line"]))
        if event == "group_begin":
            last = r
        if event in ("progress", "group_end") and r["wall_us"] > last["wall_us"]:
            dt = r["wall_us"] - last["wall_us"]
            read = cpu_us(r, ("read", "host_read")) - cpu_us(last, ("read", "host_read"))
            wait = cpu_us(r, ("first_wait", "reuse_wait")) - cpu_us(last, ("first_wait", "reuse_wait"))
            upload = cpu_us(r, ("upload", "sync_set", "mapped_set")) - cpu_us(last, ("upload", "sync_set", "mapped_set"))
            rb, tb = (r[k] - last[k] for k in ("read_requested_bytes", "transfer_logical_bytes"))
            interval = dict(identifier, end_event=event, route=r["route"], dt_s=dt/1e6,
                            estimated_end_process_s=aligned(r["load_elapsed_us"]), model_end_us=r["load_elapsed_us"],
                            read_bytes_delta=rb, transfer_bytes_delta=tb, read_MiBps=rb/MIB/(dt/1e6),
                            transfer_MiBps=tb/MIB/(dt/1e6), read_pct=100*read/dt, wait_pct=100*wait/dt,
                            upload_pct=100*upload/dt, other_pct=100*(dt-read-wait-upload)/dt,
                            completed_tensors=r["completed_tensors"], read_cumulative=r["read_requested_bytes"],
                            transfer_cumulative=r["transfer_logical_bytes"], active_tensor=r["active"]["tensor"],
                            shard=r["active"]["shard"], tensor_start_file_offset=r["active"]["tensor_file_offset"],
                            tensor_name=tensor_name(r["active"]))
            for op, stats in r["operations"].items():
                prev = counters(last, op)
                interval[f"{op}_calls_delta"] = stats["calls"] - prev.get("calls", 0)
                interval[f"{op}_time_us_delta"] = stats["sum_us"] - prev.get("sum_us", 0)
                interval[f"{op}_interval_max_us"] = stats["interval_max_us"]
            rows["progress"].append(interval)
            last = r
        if event == "group_end":
            rows["groups"].append(dict(identifier, wall_us=r["wall_us"], classified_us=r["classified_us"],
                                       unclassified_us=r["unclassified_us"], completed_tensors=r["completed_tensors"],
                                       read_bytes=r["read_requested_bytes"], transfer_bytes=r["transfer_logical_bytes"],
                                       status=r["status"], estimated_end_process_s=aligned(r["load_elapsed_us"])))
            for operation, stats in r["operations"].items():
                flat = {k: v for k, v in stats.items() if k != "histogram"}
                bins = dict(zip(("lt_100", "100_999", "1000_4999", "5000_9999", "10000_19999", "20000_49999",
                                 "50000_99999", "100000_499999", "500000_999999", "ge_1000000"), stats["histogram"]))
                rows["operations"].append(dict(identifier, operation=operation, **flat, avg_us=stats["sum_us"]/stats["calls"], **bins))
            for rank, wait in enumerate(r["long_waits"], 1):
                pos = wait["position"]
                rows["waits"].append(dict(identifier, rank=rank, operation=wait["op"], start_model_us=wait["start_us"],
                                          duration_us=wait["duration_us"], estimated_start_s=aligned(wait["start_us"]),
                                          tensor_name=tensor_name(pos), **pos))



def write_progress_chart(path, intervals, runs):
    labels = list(dict.fromkeys(x["run"] for x in intervals))
    caps = {r["run"]: r["cap_s"] for r in runs}
    colors = {"read_pct": "#234e82", "wait_pct": "#b5471b", "upload_pct": "#178074", "other_pct": "#888888"}
    tmax = max(x["estimated_end_process_s"]-caps[x["run"]] for x in intervals)
    ticks = range(0, 1 + int(tmax // 10) * 10, 10)
    height = 119 + 138*len(labels)
    sx = 625/tmax
    x0 = 72
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 {height}" role="img">',
        '<title>CPU time fractions during each recorded progress interval</title>',
        '<desc>Read, event wait, tensor set API and other wall-time fractions by diagnostic run.</desc>',
        '<rect width="100%" height="100%" fill="#fff"/>',
        '<g fill="#182535" font-family="sans-serif" font-size="13">',
        '<text x="30" y="26" font-size="17">CPU time share by recorded interval</text>',
    ]
    for i, (name, color) in enumerate(colors.items()):
        x = 30 + i*167
        out += [f'<rect x="{x}" y="41" width="12" height="12" fill="{color}"/>',
                f'<text x="{x+18}" y="52">{("Read", "Event wait", "Tensor set API", "Other")[i]}</text>']
    for i, name in enumerate(labels):
        y = 84+i*138
        out.append(f'<text x="{x0}" y="{y}">{escape(name)}</text>')
        out.append(f'<rect x="{x0}" y="{y+8}" width="{625}" height="77" fill="#f2f4f6" stroke="#d1d5db"/>')
        for r in (x for x in intervals if x["run"] == name):
            right = r["estimated_end_process_s"] - caps[name]
            left = max(0.0, right - r["dt_s"])
            y_bottom = y+85
            for k, color in colors.items():
                dy = 0.77*r[k]
                y_bottom -= dy
                out.append(f'<rect x="{x0+left*sx:.3f}" y="{y_bottom:.3f}" '
                           f'width="{max(0.15,(right-left)*sx):.3f}" height="{max(0,dy):.3f}" fill="{color}"/>')
            out.append(f'<path d="M{x0+right*sx:.3f},{y+8}v77" stroke="#ffffff" stroke-width="0.7"/>')
        out += [f'<text x="28" y="{y+16}">100%</text>', f'<text x="44" y="{y+85}">0%</text>']
        for tick in ticks:
            out.append(f'<text x="{x0+tick*sx:.3f}" y="{y+104}" text-anchor="middle">{tick}</text>')
    out += [f'<text x="384" y="{height-13}" text-anchor="middle">Seconds from buffers_ready (actual intervals)</text>',
            '</g></svg>']
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("logs", type=Path, help="Root containing r44-model-load-20261126 and its child run folders")
    p.add_argument("out", type=Path)
    p.add_argument("--tensors", type=Path, default=TENSOR_TABLE, help="Preserved PR30904 tensor metadata CSV")
    args = p.parse_args()
    iq3 = [x for x in load_csv(args.tensors) if x["model"] == "IQ3"]
    tensors = {int(x["absolute_offset"]): x["tensor"] for x in iq3}
    require(len(iq3) == len(tensors) == 1239 and sum(int(x["payload_bytes"]) for x in iq3) == 81950791260,
            "Unexpected IQ3 tensor metadata")
    rows = {name: [] for name in ("runs", "boundaries", "groups", "operations", "progress",
                                "waits", "resources", "adlx", "ram_selected", "input_hashes")}
    controllers = sorted((args.logs / "r44-model-load-20261126").glob("R44-*.result.json"))
    require(controllers, "Missing controller results")
    for path in controllers:
        controller = load_json(path)
        summarize(args.logs, controller, rows, tensors)
        run = controller["Run"]
        matrix_dir = controller["Batch"].rsplit("\\", 1)[-1]
        for metadata in (path, args.logs / "matrix" / matrix_dir / "matrix-result.json"):
            data = metadata.read_bytes()
            rows["input_hashes"].append(dict(run=run["MatrixRunId"], mode=controller["Mode"],
                                             path=metadata.relative_to(args.logs).as_posix(),
                                             bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    args.out.mkdir(parents=True, exist_ok=True)
    for name, data in rows.items():
        write_csv(args.out / f"{name}.csv", data)
    if rows["progress"]:
        write_progress_chart(args.out / "progress.svg", rows["progress"], rows["runs"])
    for run in rows["runs"]:
        print(run["run"], f"cap→Context {run['cap_to_context_s']:.3f}s", f"diagnostic records {run['diag_records']}")


if __name__ == "__main__":
    main()
