#!/usr/bin/env python3
"""Read-only, content-free summary of Antigravity CLI v1.5.18 logs."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sqlite3

BLOBS = {
    "gen_metadata": ("data",),
    "executor_metadata": ("data",),
    "trajectory_metadata_blob": ("data",),
    "steps": ("metadata", "error_details", "permissions", "task_details",
              "render_info", "step_payload"),
}
TABLES = (*BLOBS, "parent_references", "battle_mode_infos", "trajectory_meta")
KEYWORDS = ("token", "usage", "quota", "cache", "thinking", "latency",
            "duration", "approval", "permission", "tool_call", "compact",
            "compression", "error")
SOURCE = re.compile(r"^[IWEF]\d{4}\s+\S+\s+\d+\s+([\w.-]+\.go:\d+)\]")


def classify(value):
    if value is None:
        return "NULL"
    if not value:
        return "EMPTY"
    if isinstance(value, str):
        value = value.encode("utf-8")
    if not isinstance(value, bytes):
        return "OTHER_TYPE"
    if value.startswith(b"\x1f\x8b"):
        return "GZIP_MAGIC"
    if value.startswith(b"\x28\xb5\x2f\xfd"):
        return "ZSTD_MAGIC"
    if value[:2] in (b"\x78\x01", b"\x78\x9c", b"\x78\xda"):
        return "POSSIBLE_ZLIB"
    try:
        json.loads(value.decode("utf-8"))
        return "JSON"
    except (ValueError, UnicodeError, RecursionError):
        return "OTHER_BINARY_OR_TEXT"


def inspect_db(path):
    path = path.resolve(strict=True)
    with path.open("rb") as f:
        if f.read(16) != b"SQLite format 3\x00":
            raise ValueError("not a SQLite database")
    if any(Path(str(path) + s).exists() for s in ("-wal", "-shm", "-journal")):
        raise ValueError("SQLite sidecar exists; close CLI and use a consistent snapshot")
    con = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)
    try:
        con.execute("PRAGMA query_only=ON")
        con.execute("PRAGMA trusted_schema=OFF")
        tables = {row[0] for row in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        if not set(TABLES).issubset(tables):
            raise ValueError("unrecognized conversation schema")
        counts = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                  for t in TABLES}
        formats = {}
        for t, columns in BLOBS.items():
            for c in columns:
                formats[f"{t}.{c}"] = dict(Counter(
                    classify(v) for (v,) in con.execute(f"SELECT {c} FROM {t}")))
        step_counts = list(con.execute(
            "SELECT step_type,status,COUNT(*) FROM steps "
            "GROUP BY step_type,status ORDER BY step_type,status"))
        step_formats = list(con.execute(
            "SELECT step_format,COUNT(*) FROM steps GROUP BY step_format ORDER BY step_format"))
        return {"bytes": path.stat().st_size, "table_counts": counts,
                "blob_formats": formats, "step_type_status_counts": step_counts,
                "step_format_counts": step_formats}
    finally:
        con.close()


def inspect_log(path):
    counts = {k: Counter() for k in KEYWORDS}
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            lower = line.lower()
            match = SOURCE.match(line)
            source = match.group(1) if match else "UNKNOWN_SOURCE"
            for k in KEYWORDS:
                if k in lower:
                    counts[k][source] += 1
    return {k: {"lines": sum(c.values()), "sources": dict(c)}
            for k, c in counts.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, action="append", default=[])
    parser.add_argument("--log", type=Path, action="append", default=[])
    args = parser.parse_args()
    if not args.db and not args.log:
        parser.error("specify at least one --db or --log")
    result = {"databases": [], "logs": [], "errors": [],
              "note": "Counts are not token usage, model calls, approvals or failures."}
    for kind, paths, inspect in (("databases", args.db, inspect_db),
                                 ("logs", args.log, inspect_log)):
        for index, path in enumerate(paths, 1):
            try:
                result[kind].append({"input_index": index, **inspect(path)})
            except (OSError, ValueError, sqlite3.Error) as exc:
                # Do not disclose paths, raw SQL errors or log contents.
                result["errors"].append({"kind": kind, "input_index": index,
                                         "error_type": type(exc).__name__})
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
