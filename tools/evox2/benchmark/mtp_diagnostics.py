"""Parse opt-in MTP records. Timers are inclusive; only roots form totals."""
import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

FIELDS = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")
COUNTERS = {"full_rebuilds", "stale_rebuilds", "copied_cells", "appended_cells",
            "scan_steps", "logical_new", "padded_new", "rows", "bytes", "getter_us", "copy_us"}


def summarize(lines, result=None):
    starts, ends, issues = {}, {}, []
    for line in lines:
        if "mtp_diag v=" not in line:
            continue
        record = dict(FIELDS.findall(line[line.index("mtp_diag v="):]))
        if record.get("v") != "1":
            issues.append("Unsupported record schema")
            continue
        try:
            for key in ("t0_us", "t1_us", "elapsed_us", "complete", "rc"):
                record[key] = int(record[key])
            if record["kind"] not in ("begin", "end"):
                raise ValueError("Invalid kind")
            key = record["id"]
            records = starts if record["kind"] == "begin" else ends
            if key in records:
                issues.append("Duplicate event: " + key)
            records[key] = record
        except (KeyError, ValueError):
            issues.append("Malformed diagnostic record")
    if not starts and not ends:
        return {"SchemaVersion": 1, "Status": "MissingDiagnostics", "Complete": False,
                "Issues": ["No diagnostic records"], "Events": [], "Groups": []}
    for key in starts.keys() ^ ends.keys():
        issues.append("Unpaired event: " + key)
    ctx_roles, mem_roles = {}, {}
    for e in ends.values():
        if e.get("event") == "context":
            ctx_roles[e.get("ctx")] = e.get("role")
            mem_roles[e.get("mem")] = e.get("role")
    events = list(ends.values())
    # Cross-DLL parents are optional: correlate enclosing server/common operations
    # on the same thread. Do not infer attribution across asynchronous workers.
    containers = sorted((e for e in events if e.get("domain") in ("server", "common")),
                        key=lambda e: e["elapsed_us"])
    children = defaultdict(list)
    unmatched = 0
    for e in events:
        if not e["complete"] or e["t1_us"] < e["t0_us"] or e["elapsed_us"] < 0:
            issues.append("Incomplete/invalid event: " + e["id"])
        if e["id"] not in starts:
            continue
        parent = ends.get(e.get("parent"))
        if parent and (parent.get("thread") != e.get("thread") or
                       not parent["t0_us"] <= e["t0_us"] <= e["t1_us"] <= parent["t1_us"]):
            issues.append("Invalid nesting: " + e["id"])
            parent = None
        if not parent:
            parent = next((p for p in containers if p["id"] != e["id"] and p["elapsed_us"] > e["elapsed_us"] and
                           p.get("thread") == e.get("thread") and
                           p["t0_us"] <= e["t0_us"] <= e["t1_us"] <= p["t1_us"]), None)
        e["ResolvedParent"] = parent["id"] if parent else None
        if parent:
            children[parent["id"]].append(e)
        e["ResolvedRole"] = mem_roles.get(e.get("mem")) or ctx_roles.get(e.get("ctx")) or e.get("role", "unknown")
        e["ResolvedPhase"] = e.get("phase", "unknown")
    by_id = {e["id"]: e for e in events}
    for e in events:
        p, visited = e, {e["id"]}
        while p.get("ResolvedParent"):
            p = by_id[p["ResolvedParent"]]
            if p["id"] in visited:
                issues.append("Parent cycle: " + e["id"])
                break
            visited.add(p["id"])
            if e["ResolvedPhase"] == "unknown":
                e["ResolvedPhase"] = p.get("ResolvedPhase", p.get("phase", "unknown"))
            if e["ResolvedRole"] == "unknown":
                e["ResolvedRole"] = p.get("ResolvedRole", p.get("role", "unknown"))
        if e["ResolvedPhase"] == "unknown":
            unmatched += 1
        child_time = interval_length((c["t0_us"], c["t1_us"]) for c in children[e["id"]])
        e["ExclusiveUs"] = max(0, e["elapsed_us"] - child_time)
    groups = {}
    for e in events:
        if not e["complete"]:
            continue
        key = (e["ResolvedPhase"], e["ResolvedRole"], e.get("domain"), e.get("event"),
               e.get("path", ""), e.get("n_query", ""))
        g = groups.setdefault(key, {"Phase": key[0], "Role": key[1], "Domain": key[2],
                                   "Event": key[3], "Path": key[4], "Queries": key[5],
                                   "Calls": 0, "InclusiveUs": 0, "ExclusiveUs": 0,
                                   "CounterSums": {}})
        g["Calls"] += 1
        g["InclusiveUs"] += e["elapsed_us"]
        g["ExclusiveUs"] += e["ExclusiveUs"]
        for name in COUNTERS & e.keys():
            try:
                g["CounterSums"][name] = g["CounterSums"].get(name, 0) + int(e[name])
            except ValueError:
                issues.append("Invalid counter: " + e["id"] + "/" + name)
    generation_intervals = [(e["t0_us"], e["t1_us"]) for e in events
                            if e.get("domain") == "server" and e["complete"] and
                            e["ResolvedPhase"] == "generation"]
    covered = interval_length(generation_intervals)
    result = result or {}
    generation_us = result.get("GenerationEvalMilliseconds")
    remainder = None if generation_us is None else float(generation_us) * 1000 - covered
    alignment_warning = "Covered generation exceeds reported time; check phase alignment" if remainder is not None and remainder < 0 else None
    return {"SchemaVersion": 1, "Status": "Complete" if not issues else "Incomplete",
            "Complete": not issues, "Issues": issues, "UnmatchedPhaseEvents": unmatched,
            "Modes": sorted({e.get("mode") for e in events}),
            "CoveredServerGenerationUs": covered,
            "ApproximateUncoveredGenerationUs": remainder,
            "PhaseAlignmentWarning": alignment_warning,
            "Accounting": "Group times are inclusive/nested. Never sum all groups; coverage uses interval union. "
                          "ExclusiveUs excludes matched same-thread children, not GPU kernel time.",
            "Events": events, "Groups": sorted(groups.values(), key=lambda g: (g["Phase"], g["Role"], g["Domain"], g["Event"], g["Path"], g["Queries"]))}


def interval_length(intervals):
    intervals = sorted(intervals)
    total = 0
    if not intervals:
        return total
    start, end = intervals[0]
    for a, b in intervals[1:]:
        if a <= end:
            end = max(end, b)
        else:
            total += end - start
            start, end = a, b
    return total + end - start


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_directory", type=Path)
    args = parser.parse_args()
    root = args.run_directory
    result_path = root / "result.json"
    result = json.loads(result_path.read_text(encoding="utf-8-sig")) if result_path.exists() else {}
    report = summarize((root / "stderr.log").read_text(encoding="utf-8-sig", errors="replace").splitlines(), result)
    (root / "mtp-diagnostics.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    fields = ["Phase", "Role", "Domain", "Event", "Path", "Queries", "Calls", "InclusiveUs", "ExclusiveUs", "CounterSums"]
    with (root / "mtp-diagnostics.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in report["Groups"]:
            writer.writerow({**row, "CounterSums": json.dumps(row["CounterSums"], sort_keys=True)})
    print(f'MTP diagnostics: {report["Status"]}; {len(report["Events"])} events; {report.get("UnmatchedPhaseEvents", 0)} unmatched phases')
    return 0 if report["Complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
