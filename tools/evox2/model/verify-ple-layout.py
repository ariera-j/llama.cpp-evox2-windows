#!/usr/bin/env python3
"""Inspect a qwen4exp PLE tensor layout without modifying the GGUF file."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


JOINED = "per_layer_token_embd.weight"
HEAD_RE = re.compile(r"ple_ngram_embd\.(\d+)\.weight$")


def field_ints(field):
    return [int(x) for x in field.contents()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument(
        "--gguf-py",
        type=Path,
        required=True,
        help="Path to the external llama.cpp fork's gguf-py directory",
    )
    parser.add_argument(
        "--expect",
        choices=("split", "joined", "either"),
        default="either",
    )
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()

    sys.path.insert(0, str(args.gguf_py.resolve()))
    import gguf  # type: ignore  # noqa: E402

    reader = gguf.GGUFReader(args.input, "r")

    architecture_field = reader.fields.get("general.architecture")
    architecture = (
        architecture_field.contents()
        if architecture_field is not None
        else None
    )

    offsets_field = reader.fields.get("qwen4exp.ple.head_offsets")
    vocabs_field = reader.fields.get("qwen4exp.ple.head_vocab_sizes")

    offsets = field_ints(offsets_field) if offsets_field is not None else []
    vocabs = field_ints(vocabs_field) if vocabs_field is not None else []

    tensors = list(reader.tensors)
    names = {tensor.name for tensor in tensors}
    joined = next((t for t in tensors if t.name == JOINED), None)

    heads = {}
    for tensor in tensors:
        match = HEAD_RE.match(tensor.name)
        if match:
            heads[int(match.group(1))] = tensor

    issues = []

    if offsets_field is None or vocabs_field is None:
        issues.append(
            "Missing qwen4exp.ple.head_offsets or qwen4exp.ple.head_vocab_sizes."
        )
    elif len(offsets) != len(vocabs):
        issues.append(
            f"Metadata has {len(offsets)} offsets but {len(vocabs)} vocab sizes."
        )

    if joined is not None and heads:
        layout = "mixed"
        issues.append("Both joined and per-head PLE tensors are present.")
    elif joined is not None:
        layout = "joined"
    elif heads:
        layout = "split"
    else:
        layout = "missing"
        issues.append("No joined or per-head PLE tensor layout was found.")

    if layout == "split" and offsets and vocabs:
        expected_count = len(offsets)

        if len(heads) != expected_count:
            issues.append(
                f"Expected {expected_count} per-head tensors, found {len(heads)}."
            )

        for index in range(expected_count):
            tensor = heads.get(index)
            if tensor is None:
                issues.append(f"Missing ple_ngram_embd.{index}.weight.")
                continue

            rows = int(tensor.data.shape[0])
            expected_rows = int(vocabs[index])
            if rows != expected_rows:
                issues.append(
                    f"Head {index} has {rows} rows, expected {expected_rows}."
                )

    if layout == "joined" and offsets and vocabs and joined is not None:
        needed_rows = offsets[-1] + vocabs[-1]
        actual_rows = int(joined.data.shape[0])
        if actual_rows < needed_rows:
            issues.append(
                f"Joined tensor has {actual_rows} rows, "
                f"but metadata requires at least {needed_rows}."
            )

    if args.expect != "either" and layout != args.expect:
        issues.append(f"Expected {args.expect} layout, observed {layout}.")

    head_types = sorted(
        {str(tensor.tensor_type) for tensor in heads.values()}
    )

    report = {
        "schema_version": 1,
        "file": str(args.input.resolve()),
        "architecture": architecture,
        "layout": layout,
        "expected_layout": args.expect,
        "metadata_head_count": len(offsets),
        "per_head_tensor_count": len(heads),
        "head_tensor_types": head_types,
        "joined_tensor_present": joined is not None,
        "valid": not issues,
        "issues": issues,
    }

    print(json.dumps(report, ensure_ascii=False, indent=2))

    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    return 0 if not issues else 2


if __name__ == "__main__":
    raise SystemExit(main())
