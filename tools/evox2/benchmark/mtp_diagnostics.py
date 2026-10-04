"""Parse opt-in MTP records. Timers are inclusive; only roots form totals."""
import argparse
import csv
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

FIELDS = re.compile(r"([A-Za-z0-9_]+)=([^\s]+)")
COUNTERS = {"full_rebuilds", "stale_rebuilds", "copied_cells", "appended_cells",
            "noop_observed", "noop_suppressed", "stale_marked", "pending_stale_preserved",
            "scan_steps", "logical_new", "padded_new", "rows", "bytes", "getter_us", "copy_us"}


def summarize(lines, result=None):
    starts, ends, issues = {}, {}, []
    probe_candidates, last_record, task_started = [], None, False
    for line_number, line in enumerate(lines, 1):
        if "mtp_diag v=" not in line:
            # common_context_can_seq_rm deliberately tries seq_rm(0, 1, -1)
            # during startup. A false result followed immediately by this common
            # log means unsupported capability, not a failed inference request.
            if (not task_started and last_record and
                    "the context does not support partial sequence removal" in line and
                    re.search(r"\bcmn\s+common_conte(?:xt_can_seq_rm)?:", line)):
                e = last_record
                if (e.get("kind") == "end" and e.get("domain") == "memory" and
                        e.get("event") == "seq_rm" and e.get("phase") in ("unknown", "setup") and
                        e.get("parent") == "none" and e.get("rc") == -1 and e.get("complete") == 0 and
                        (e.get("seq"), e.get("pos_first"), e.get("pos_last")) == ("0", "1", "-1")):
                    probe_candidates.append((e["id"], line_number))
            last_record = None
            continue
        record = dict(FIELDS.findall(line[line.index("mtp_diag v="):]))
        if record.get("v") != "1":
            issues.append("Unsupported record schema")
            last_record = None
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
            last_record = record
            if (record.get("domain") == "server" and record.get("event") == "target_evaluation" and
                    record.get("phase") in ("prompt", "generation", "mixed")):
                task_started = True
        except (KeyError, ValueError):
            issues.append("Malformed diagnostic record")
            last_record = None
    if not starts and not ends:
        return {"SchemaVersion": 1, "Status": "MissingDiagnostics", "Complete": False,
                "Issues": ["No diagnostic records"], "Events": [], "Groups": []}
    for key in starts.keys() ^ ends.keys():
        issues.append("Unpaired event: " + key)
    expected_refusals = []
    for root_id, marker_line in probe_candidates:
        root = ends[root_id]
        children = [e for e in ends.values() if e.get("parent") == root_id]
        if root_id not in starts or len(children) != 1:
            continue
        child = children[0]
        if (child["id"] not in starts or child.get("domain") != "memory" or
                child.get("event") != "seq_rm_recurrent" or child["rc"] != -1 or child["complete"] != 0 or
                child.get("thread") != root.get("thread") or
                not root["t0_us"] <= child["t0_us"] <= child["t1_us"] <= root["t1_us"]):
            continue
        root["ExpectedRefusal"] = child["ExpectedRefusal"] = True
        expected_refusals.append({"RootId": root_id, "ChildId": child["id"], "MarkerLine": marker_line,
                                 "Reason": "Startup partial-sequence-removal capability probe refused"})
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
        if ((not e["complete"] and not e.get("ExpectedRefusal")) or
                e["t1_us"] < e["t0_us"] or e["elapsed_us"] < 0):
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
        if not e["complete"] and not e.get("ExpectedRefusal"):
            continue
        key = (e["ResolvedPhase"], e["ResolvedRole"], e.get("domain"), e.get("event"),
               e.get("path", ""), e.get("n_query", ""))
        g = groups.setdefault(key, {"Phase": key[0], "Role": key[1], "Domain": key[2],
                                   "Event": key[3], "Path": key[4], "Queries": key[5],
                                   "Calls": 0, "ExpectedRefusals": 0, "InclusiveUs": 0, "ExclusiveUs": 0,
                                   "CounterSums": {}})
        g["Calls"] += 1
        g["ExpectedRefusals"] += int(bool(e.get("ExpectedRefusal")))
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
            "ExpectedRefusals": expected_refusals,
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


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def update_csv(path, updates, key):
    if not path.exists():
        raise ValueError("Required CSV is missing: " + str(path))
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields, rows = reader.fieldnames, list(reader)
    if not fields or key not in fields:
        raise ValueError("Invalid CSV schema: " + str(path))
    for row in rows:
        for name, value in updates.get(row[key], {}).items():
            if name in fields:
                row[name] = value
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(rows)


def summarize_run(root, repair=False):
    result_path = root / "result.json"
    result = json.loads(result_path.read_text(encoding="utf-8-sig")) if result_path.exists() else {}
    report = summarize((root / "stderr.log").read_text(encoding="utf-8-sig", errors="replace").splitlines(), result)
    write_json(root / "mtp-diagnostics.json", report)
    fields = ["Phase", "Role", "Domain", "Event", "Path", "Queries", "Calls", "ExpectedRefusals", "InclusiveUs", "ExclusiveUs", "CounterSums"]
    with (root / "mtp-diagnostics.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in report["Groups"]:
            writer.writerow({**row, "CounterSums": json.dumps(row["CounterSums"], sort_keys=True)})
    if (repair and report["Complete"] and result.get("Status") == "DIAGNOSTIC_INCOMPLETE" and
            result.get("DiagnosticStatus") == "Incomplete" and result.get("ExitCode") == 0 and
            not result.get("RunException")):
        summary_path = root / "summary.csv"
        update_csv(summary_path, {result["RunId"]: {"Status": "OK"}}, "RunId")
        result["DiagnosticRecovery"] = {
            "RecoveredAt": datetime.now(timezone.utc).isoformat(), "PreviousStatus": result["Status"],
            "PreviousDiagnosticError": result.get("DiagnosticError"),
            "Reason": "Existing raw log re-parsed as complete; no inference rerun"}
        result["Status"], result["DiagnosticStatus"] = "OK", "Complete"
        result.pop("DiagnosticError", None)
        write_json(result_path, result)
    print(f'MTP diagnostics: {report["Status"]}; {len(report["Events"])} events; {report.get("UnmatchedPhaseEvents", 0)} unmatched phases')
    return report, result


def repair_matrix(root):
    matrix_path = root / "matrix-result.json"
    matrix = json.loads(matrix_path.read_text(encoding="utf-8-sig"))
    statuses = {}
    for run in matrix["Runs"]:
        directory = run.get("ChildRunDirectory")
        if not directory:
            raise ValueError("Run has no child directory: " + run["MatrixRunId"])
        directory = Path(directory)
        child = json.loads((directory / "result.json").read_text(encoding="utf-8-sig"))
        if child.get("RunId") != run.get("ChildRunId"):
            raise ValueError("Child identity mismatch: " + run["MatrixRunId"])
        report, child = summarize_run(directory, repair=True)
        if not report["Complete"] or child.get("Status") != "OK" or child.get("ExitCode") != 0:
            raise ValueError("Run still failed/incomplete: " + run["MatrixRunId"])
        statuses[run["MatrixRunId"]] = child["Status"]
    # Restore only an entirely finished matrix. Partial/stopped matrices must not
    # claim completion or hide runs that were never collected.
    if len(matrix["Runs"]) != matrix["RunCountPlanned"] or len(statuses) != len(matrix["Runs"]):
        raise ValueError("Matrix is only partially collected; child sidecars updated, matrix status retained")
    recovery = {"RecoveredAt": datetime.now(timezone.utc).isoformat(),
                "PreviousComplete": matrix.get("Complete"), "PreviousStoppedEarly": matrix.get("StoppedEarly"),
                "PreviousStatusCounts": matrix.get("StatusCounts"), "Reason": "Diagnostic-only recovery; no inference rerun"}
    for run in matrix["Runs"]:
        run["MatrixStatus"] = statuses[run["MatrixRunId"]]
    for row in matrix["Results"]:
        row["ChildStatus"] = statuses[row["MatrixRunId"]]
    update_csv(root / "matrix-runs.csv", {k: {"MatrixStatus": v} for k, v in statuses.items()}, "MatrixRunId")
    update_csv(root / "matrix-results.csv", {k: {"ChildStatus": v} for k, v in statuses.items()}, "MatrixRunId")
    matrix.update(Complete=True, StoppedEarly=False, RunCountFinished=len(statuses), StatusCounts={"OK": len(statuses), "NonOK": 0},
                  DiagnosticRecovery=recovery)
    write_json(matrix_path, matrix)
    print("MTP matrix recovery: complete; all existing runs OK; no model execution")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("--repair-matrix", action="store_true")
    args = parser.parse_args()
    if args.repair_matrix:
        repair_matrix(args.run_directory)
        return 0
    report, _ = summarize_run(args.run_directory)
    return 0 if report["Complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
