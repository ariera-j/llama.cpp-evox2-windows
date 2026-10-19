#!/usr/bin/env python3
"""Audit opt-in MTP rollback and replay coverage for one C/A/B matrix scenario.

Consumes the ZIP normally uploaded from Invoke-BenchmarkMatrix.ps1 (one archive
with C, A and B child runs), or an extracted directory. Prints a JSON report
and exits 0 only when the requested synthetic branch was actually exercised,
all three runs succeeded, and deterministic C/A/B continuation output matches.

NOT a valid-output test in synthetic scenarios: --spec-synth-rates deliberately
replaces actual target verification and changes generated token semantics.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path

EVENT = re.compile(r"mtp_rollback_diag_v1\s+(.*)")
KV = re.compile(r"([A-Za-z_]+)=([^\s]+)")
RATE = re.compile(r"\[\s*Prompt:\s*[\d.]+\s*t/s\s*\|\s*Generation:\s*[\d.]+\s*t/s\s*\]")
ARMS = {"C": ("0", "0"), "A": ("1", "0"), "B": ("1", "1")}
SYNTH = {"natural": None, "reject-zero": "0,0",
         "reject-after-one": "1,0", "accept-all": "1,1"}


def _read_runs(source: Path):
    if source.is_file() and zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            members = archive.namelist()
            prefixes = sorted({s.rsplit("/", 1)[0] for s in members if s.endswith("/result.json")})
            for prefix in prefixes:
                def get(name):
                    key = prefix + "/" + name
                    return archive.read(key).decode("utf-8-sig", "replace")
                yield prefix, get
    elif source.is_dir():
        for p in sorted(source.rglob("result.json")):
            def get(name, parent=p.parent):
                return (parent / name).read_text("utf-8-sig")
            yield str(p.parent), get
    else:
        raise ValueError("provide matrix ZIP or directory containing per-run result.json files")


def _events(stderr: str):
    found = []
    for line in stderr.splitlines():
        m = EVENT.search(line)
        if not m:
            continue
        found.append(dict(KV.findall(m.group(1))))
    return found


def _clean_stdout(s: str) -> str:
    # stdout includes model banner and a per-run throughput notice; remove
    # only the volatile timing notice, not any produced text.
    return RATE.sub("", s.replace("\r\n", "\n")).strip()


def _summary(case: str, ev: list[dict]) -> dict:
    counter = Counter(x.get("event") for x in ev)
    decisions = [x for x in ev if x.get("event") == "decision"]
    regular = [x for x in decisions if x.get("replay") == "0"]
    restore = counter["checkpoint_restore"]
    replay = sum(x.get("replay") == "1" for x in ev if x.get("event") == "commit")
    reject = sum(int(x.get("rollback", "0")) > 0 for x in regular)
    full = sum(int(x.get("rollback", "0")) == 0 for x in regular)
    first = Counter(x.get("accepted") for x in regular)
    errors = []
    if counter["init"] != 1:
        errors.append("expected exactly one init event")
    if not regular or counter["draft"] <= 0 or counter["commit"] <= 0:
        errors.append("missing draft/decision/commit coverage")
    if case == "reject-zero":
        if restore <= 0 or replay <= 0 or reject <= 0:
            errors.append("forced zero-accept restore/replay not exercised")
        if any(x.get("accepted") != "0" for x in regular):
            errors.append("some original decisions accepted draft tokens under 0,0")
    if case == "reject-after-one":
        if restore <= 0 or replay <= 0 or reject <= 0:
            errors.append("forced partial-accept restore/replay not exercised")
        if not any(x.get("accepted") == "1" and int(x.get("rollback", "0")) > 0 for x in regular):
            errors.append("no decision accepting exactly one draft followed by rollback")
    if case == "accept-all":
        if not full or reject or restore:
            errors.append("accept-all unexpectedly had a rejection/restore or no full acceptance")
    if case == "natural" and not regular:
        errors.append("no natural verification decisions")
    if restore != replay:
        errors.append(f"checkpoint restores {restore} != replay commits {replay}")
    return {"events": dict(counter), "draft_decisions": len(regular),
            "rejected_rounds": reject, "full_accept_rounds": full,
            "accepted_histogram": dict(first), "checkpoint_restores": restore,
            "replay_commits": replay, "errors": errors}


def inspect(source: Path, scenario: str) -> dict:
    if scenario not in SYNTH:
        raise ValueError(f"unknown scenario {scenario}")
    arms = {}
    problems = []
    for prefix, get in _read_runs(source):
        try:
            result = json.loads(get("result.json"))
            cond = json.loads(get("conditions.json"))
            env = cond.get("Environment", {})
            arm = env.get("LLAMA_MTP_ROLLBACK_TAG")
            if arm not in ARMS:
                problems.append(f"{prefix}: missing/invalid rollback arm tag")
                continue
            if arm in arms:
                problems.append(f"duplicate arm {arm}")
                continue
            exp_sb, exp_flat = ARMS[arm]
            if env.get("LLAMA_MTP_DRAFT_PREFILL_KV_CROP") != exp_sb or env.get("LLAMA_MTP_EH_PROJ_FLATTEN") != exp_flat:
                problems.append(f"{arm}: incorrect Stage-B/flatten flags")
            if env.get("LLAMA_MTP_ROLLBACK_DIAG") != "1":
                problems.append(f"{arm}: rollback trace not enabled")
            forced = env.get("LLAMA_MTP_ROLLBACK_FORCE_CKPT")
            if forced != ("0" if scenario == "natural" else "1"):
                problems.append(f"{arm}: force checkpoint mode mismatch {forced}")
            args = cond.get("Arguments", [])
            argline = " ".join(args) if isinstance(args, list) else str(args)
            expected = SYNTH[scenario]
            if expected is not None and f"--spec-synth-rates {expected}" not in argline:
                problems.append(f"{arm}: expected synthetic rates {expected} missing")
            if expected is None and "--spec-synth-rates" in argline:
                problems.append(f"{arm}: natural case must not use synthetic acceptance")
            if result.get("Status") != "OK" or result.get("ExitCode") != 0:
                problems.append(f"{arm}: run did not finish OK")
            ev = _events(get("stderr.log"))
            summary = _summary(scenario, ev)
            for error in summary["errors"]:
                problems.append(f"{arm}: {error}")
            normalized = _clean_stdout(get("stdout.log"))
            arms[arm] = {
                "run": result.get("RunId"),
                "exe_sha256": result.get("ExecutableSha256"),
                "runtime_digest": result.get("RuntimeArtifactDigest"),
                "input_identity": cond.get("InputIdentity"),
                "model_identity": cond.get("ModelIdentity"),
                "draft_model_identity": cond.get("DraftModelIdentity"),
                "prompt_tokens": result.get("PromptTokens"),
                "generated_tokens": result.get("GeneratedTokens"),
                "draft_accepted": result.get("DraftAccepted"),
                "draft_generated": result.get("DraftGenerated"),
                "normalized_stdout_sha256": hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
                "trace": summary,
            }
        except (KeyError, OSError, ValueError, json.JSONDecodeError) as exc:
            problems.append(f"{prefix}: cannot inspect: {exc}")

    if set(arms) != set(ARMS):
        problems.append(f"required arms C/A/B not all present: {sorted(arms)}")
    if len(arms) == 3:
        for field in ("exe_sha256", "runtime_digest", "prompt_tokens", "generated_tokens",
                      "input_identity", "model_identity", "draft_model_identity",
                      "normalized_stdout_sha256"):
            vals = [json.dumps(arms[a][field], sort_keys=True, ensure_ascii=False) for a in ("C", "A", "B")]
            if len(set(vals)) != 1:
                problems.append(f"C/A/B differ for {field}")
        # Branch-coverage traces should use equivalent synthetic decision paths.
        if scenario != "natural":
            for field in ("checkpoint_restores", "replay_commits", "draft_decisions"):
                vals = {a: arms[a]["trace"][field] for a in ("C", "A", "B")}
                if len(set(vals.values())) != 1:
                    problems.append(f"C/A/B differ for trace.{field}: {vals}")

    return {"schema_version": 1, "scenario": scenario, "status": "PASS" if not problems else "FAIL",
            "problems": problems, "arms": arms,
            "note": "synthetic outputs are NOT valid answers; report only C/A/B parity and event coverage"}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source", type=Path, required=True, help="matrix ZIP or extracted child-run directory")
    p.add_argument("--scenario", choices=sorted(SYNTH), required=True)
    p.add_argument("--report", type=Path)
    args = p.parse_args()
    try:
        report = inspect(args.source, args.scenario)
    except (OSError, ValueError) as exc:
        report = {"schema_version": 1, "scenario": args.scenario,
                  "status": "ERROR", "problems": [str(exc)]}
    result = json.dumps(report, ensure_ascii=False, indent=2)
    print(result)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(result + "\n", encoding="utf-8")
    return 0 if report["status"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
