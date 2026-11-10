#!/usr/bin/env python3
"""Freeze a line-aligned code prefix for 64k llama-cli PP diagnostics."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def tokenizer_count(executable: Path, model: Path, prompt_path: Path) -> int:
    command = [
        str(executable),
        "-m", str(model),
        "-f", str(prompt_path),
        "--ids", "--show-count", "--no-bos",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=180)
    if completed.returncode != 0:
        tail = completed.stderr[-2000:]
        raise RuntimeError(f"llama-tokenize failed (exit={completed.returncode}): {tail}")
    match = re.search(r"Total number of tokens:\s*(\d+)", completed.stdout)
    if not match:
        raise RuntimeError("llama-tokenize did not print a parseable token count")
    return int(match.group(1))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Original llama.cpp code corpus UTF-8 text")
    parser.add_argument("--tokenizer", type=Path, required=True, help="Matching llama-tokenize.exe")
    parser.add_argument("--model", type=Path, required=True, help="Matching Qwen PLE16 GGUF (vocab only)")
    parser.add_argument("--out", type=Path, required=True, help="Frozen prefix *.prompt.txt file")
    parser.add_argument("--max-tokens", type=int, default=61777, help="Raw no-BOS tokenizer cap (default: 61777)")
    args = parser.parse_args()

    if args.max_tokens < 1024 or args.max_tokens > 63000:
        parser.error("--max-tokens must be in [1024, 63000] to leave room for the CLI chat template")
    for path in [args.source, args.tokenizer, args.model]:
        if not path.is_file():
            parser.error(f"Missing file: {path}")
    if args.out.exists():
        parser.error(f"Output already exists; do not overwrite a frozen fixture: {args.out}")

    raw = args.source.read_bytes()
    raw.decode("utf-8")
    lines = raw.splitlines(keepends=True)
    if not lines:
        parser.error("Input is empty")
    args.out.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="evox2-code64k-") as tmp:
        candidate = Path(tmp) / "candidate.prompt.txt"
        lo = 0
        hi = len(lines) + 1
        best_tokens = 0
        # Largest number of complete input lines whose token count fits.
        while hi - lo > 1:
            mid = (lo + hi) // 2
            candidate.write_bytes(b"".join(lines[:mid]))
            count = tokenizer_count(args.tokenizer, args.model, candidate)
            print(f"prefix_lines={mid} tokens={count}", flush=True)
            if count <= args.max_tokens:
                lo = mid
                best_tokens = count
            else:
                hi = mid
        if lo == 0:
            parser.error("Even the first complete line exceeds the token cap")
        output = b"".join(lines[:lo])
        args.out.write_bytes(output)
        actual = tokenizer_count(args.tokenizer, args.model, args.out)
        if actual > args.max_tokens:
            raise RuntimeError(f"Final prefix unexpectedly exceeds cap: {actual}")
        metadata = {
            "source": str(args.source.resolve()),
            "source_sha256": sha256_file(args.source),
            "output": str(args.out.resolve()),
            "output_sha256": sha256_file(args.out),
            "output_bytes": len(output),
            "prefix_lines": lo,
            "raw_tokens_no_bos": actual,
            "max_tokens": args.max_tokens,
            "tokenizer": str(args.tokenizer.resolve()),
            "tokenizer_sha256": sha256_file(args.tokenizer),
            "model_path": str(args.model.resolve()),
            "note": "llama-cli chat template may add tokens; verify PromptTokens and truncated=0 in real runs",
        }
        metadata_path = args.out.with_name(args.out.name + ".meta.json")
        metadata_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Frozen {args.out} ({actual} raw tokens, SHA256 {metadata['output_sha256']})")
        print(f"Metadata {metadata_path}")


if __name__ == "__main__":
    main()
