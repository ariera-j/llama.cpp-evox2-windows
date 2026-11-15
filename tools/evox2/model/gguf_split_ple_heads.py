#!/usr/bin/env python3
"""Convert a qwen4exp n-gram table between its joined and per-head layouts.

Downstream adaptation of the MIT-licensed LaurentZuijdwijk/llama.cpp
converter archived on this repository's r2/legacy branch. Adapted for the r5
GGUF library (no PLE_NGRAM_EMBD enum required).

The joined per_layer_token_embd is ~20.9 GiB, past the 4 GiB buffer a Vulkan device
will accept, so it can only ever sit on the host. Each n-gram head is a contiguous row
range of that table and is ~1.3 GiB, which fits. Rows are 160 elements, a whole number
of blocks for every 32-block type, so the heads split on block boundaries and the
quantized bytes are copied through untouched: no dequantize, no requantize, no loss.
The same holds in reverse: joining concatenates the head tensors' raw bytes back into
one tensor, in head order, which reproduces the original joined layout exactly.

Direction is auto-detected from which tensors the input has: a joined
per_layer_token_embd.weight splits, a full set of ple_ngram_embd.N.weight tensors joins.

Head bounds come from the file's own ple.head_offsets and ple.head_vocab_sizes.
"""
from __future__ import annotations

import argparse
import logging
import re
import sys
from pathlib import Path

import numpy as np

# Prefer the r5 checkout's GGUF reader/writer over any pip-installed copy.
repo_root = Path(__file__).resolve().parents[3]
gguf_py = repo_root / "gguf-py"
if not gguf_py.is_dir():
    raise RuntimeError(f"r5 gguf-py directory not found: {gguf_py}")
sys.path.insert(0, str(gguf_py))

import gguf  # noqa: E402

logger = logging.getLogger("gguf-split-ple-heads")

JOINED = "per_layer_token_embd.weight"
HEAD_RE = re.compile(r"ple_ngram_embd\.(\d+)\.weight$")


def split(readers: list[gguf.GGUFReader], writer: gguf.GGUFWriter) -> None:
    reader = readers[0]
    offs = reader.fields.get("qwen4exp.ple.head_offsets")
    vocs = reader.fields.get("qwen4exp.ple.head_vocab_sizes")
    if offs is None or vocs is None:
        raise ValueError("file has no qwen4exp.ple.head_offsets / head_vocab_sizes; is it qwen4exp?")
    offs = [int(x) for x in offs.contents()]
    vocs = [int(x) for x in vocs.contents()]
    if len(offs) != len(vocs):
        raise ValueError(f"{len(offs)} head offsets but {len(vocs)} vocab sizes")

    for field in reader.fields.values():
        # a split input becomes one file, so its shard bookkeeping must not carry over
        if field.name.startswith("GGUF.") or field.name.startswith("split."):
            continue
        val_type = field.types[0]
        sub_type = field.types[-1] if val_type == gguf.GGUFValueType.ARRAY else None
        writer.add_key_value(field.name, field.contents(), val_type, sub_type=sub_type)

    tensors = [t for r in readers for t in r.tensors]
    joined = next((t for t in tensors if t.name == JOINED), None)
    if joined is None:
        raise ValueError(f"{JOINED} not found; already split?")
    if joined.data.shape[0] < offs[-1] + vocs[-1]:
        raise ValueError(f"heads need {offs[-1] + vocs[-1]} rows, table has {joined.data.shape[0]}")

    # tensor infos first, in the order the data is written below
    plan = []
    for t in tensors:
        if t.name == JOINED:
            for h, (o, v) in enumerate(zip(offs, vocs)):
                name = f"ple_ngram_embd.{h}.weight"
                data = t.data[o:o + v]
                logger.info(f"{name}: rows {o}..{o + v} ({data.nbytes / 2**30:.2f} GiB)")
                plan.append((name, data, t.tensor_type))
        else:
            plan.append((t.name, t.data, t.tensor_type))

    for name, data, qtype in plan:
        writer.add_tensor_info(name, data.shape, data.dtype, data.nbytes, qtype)

    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_ti_data_to_file()

    done = 0
    total = sum(d.nbytes for _, d, _ in plan)
    for name, data, _ in plan:
        writer.write_tensor_data(data, tensor_endianess=reader.endianess)
        done += data.nbytes
        logger.info(f"  {done / total * 100:5.1f}%  {name}")

    writer.close()


def join(readers: list[gguf.GGUFReader], writer: gguf.GGUFWriter) -> None:
    reader = readers[0]
    offs = reader.fields.get("qwen4exp.ple.head_offsets")
    vocs = reader.fields.get("qwen4exp.ple.head_vocab_sizes")
    if offs is None or vocs is None:
        raise ValueError("file has no qwen4exp.ple.head_offsets / head_vocab_sizes; is it qwen4exp?")
    offs = [int(x) for x in offs.contents()]
    vocs = [int(x) for x in vocs.contents()]
    n_heads = len(offs)

    for field in reader.fields.values():
        if field.name.startswith("GGUF.") or field.name.startswith("split."):
            continue
        val_type = field.types[0]
        sub_type = field.types[-1] if val_type == gguf.GGUFValueType.ARRAY else None
        writer.add_key_value(field.name, field.contents(), val_type, sub_type=sub_type)

    tensors = [t for r in readers for t in r.tensors]
    heads = {}
    for t in tensors:
        m = HEAD_RE.match(t.name)
        if m:
            heads[int(m.group(1))] = t
    if len(heads) != n_heads:
        raise ValueError(f"expected {n_heads} ple_ngram_embd.N tensors, found {len(heads)}; already joined?")

    qtype = heads[0].tensor_type
    for h in range(n_heads):
        if h not in heads:
            raise ValueError(f"missing ple_ngram_embd.{h}.weight")
        if heads[h].tensor_type != qtype:
            raise ValueError(f"head {h} has type {heads[h].tensor_type}, expected {qtype} "
                              "(heads must share one type to join into a single tensor)")
        if heads[h].data.shape[0] != vocs[h]:
            raise ValueError(f"head {h} has {heads[h].data.shape[0]} rows, expected {vocs[h]}")
        logger.info(f"{heads[h].name}: rows {offs[h]}..{offs[h] + vocs[h]} "
                    f"({heads[h].data.nbytes / 2**30:.2f} GiB)")

    joined_data = np.concatenate([heads[h].data for h in range(n_heads)], axis=0)

    # tensor infos first, in the order the data is written below; the joined tensor
    # takes the position of the first head so the file keeps its original ordering
    plan = []
    inserted = False
    for t in tensors:
        if HEAD_RE.match(t.name):
            if not inserted:
                plan.append((JOINED, joined_data, qtype))
                inserted = True
            continue
        plan.append((t.name, t.data, t.tensor_type))

    for name, data, qtype_ in plan:
        writer.add_tensor_info(name, data.shape, data.dtype, data.nbytes, qtype_)

    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_ti_data_to_file()

    done = 0
    total = sum(d.nbytes for _, d, _ in plan)
    for name, data, _ in plan:
        writer.write_tensor_data(data, tensor_endianess=reader.endianess)
        done += data.nbytes
        logger.info(f"  {done / total * 100:5.1f}%  {name}")

    writer.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path,
                        help="qwen4exp GGUF, pass shard 00001 of a multi-file model")
    parser.add_argument("output", type=Path,
                        help="single-file converted GGUF (no writes with --check-only)")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--check-only", action="store_true",
                        help="validate source shards, metadata and PLE tensor shape without writing")
    parser.add_argument("--expect-operation", choices=("split", "join", "auto"),
                        default="auto", help="fail rather than silently use the wrong direction")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(message)s")

    if not args.check_only and args.output.exists():
        raise SystemExit(f"Output already exists: {args.output}")
    if not args.input.is_file():
        raise SystemExit(f"Input does not exist: {args.input}")
    if args.input.resolve() == args.output.resolve():
        raise SystemExit("Refusing to overwrite source GGUF")

    paths = [args.input]
    m = re.fullmatch(r"(.*)-(\d{5})-of-(\d{5})\.gguf", args.input.name,
                     re.IGNORECASE)
    if m:
        stem, index, total = m.group(1), int(m.group(2)), int(m.group(3))
        if index != 1:
            raise SystemExit("Pass shard 00001, not a later shard")
        paths = [args.input.parent / f"{stem}-{i:05d}-of-{total:05d}.gguf"
                 for i in range(1, total + 1)]
        missing = [p.name for p in paths if not p.is_file()]
        if missing:
            raise SystemExit(f"Missing shards: {', '.join(missing)}")
        logger.info("reading %s shards", total)

    readers = [gguf.GGUFReader(path, "r") for path in paths]
    first = readers[0]
    architecture = first.fields["general.architecture"].contents()
    if architecture != "qwen4exp":
        raise SystemExit(f"Expected qwen4exp, found {architecture!r}")

    offsets_field = first.fields.get("qwen4exp.ple.head_offsets")
    sizes_field = first.fields.get("qwen4exp.ple.head_vocab_sizes")
    if offsets_field is None or sizes_field is None:
        raise SystemExit("Source lacks qwen4exp PLE head offsets / vocab sizes")
    offsets = [int(x) for x in offsets_field.contents()]
    sizes = [int(x) for x in sizes_field.contents()]
    if len(offsets) != 16 or len(sizes) != 16:
        raise SystemExit(f"COMMON-001 expects 16 PLE heads, metadata has {len(offsets)}")
    if any(size <= 0 for size in sizes) or any(off < 0 for off in offsets):
        raise SystemExit("Invalid PLE head sizes or offsets")
    if any(offsets[i] + sizes[i] > offsets[i + 1] for i in range(15)):
        raise SystemExit("PLE metadata contains overlapping head ranges")

    tensors = [t for reader in readers for t in reader.tensors]
    names = [t.name for t in tensors]
    if len(names) != len(set(names)):
        raise SystemExit("Duplicate tensor names across shards")
    joined = next((t for t in tensors if t.name == JOINED), None)
    per_head = [name for name in names if HEAD_RE.fullmatch(name)]
    if joined is not None and per_head:
        raise SystemExit("Source mixes joined and split PLE tensors")
    if joined is not None:
        if joined.data.ndim < 2:
            raise SystemExit(f"Unsupported joined PLE tensor shape: {joined.data.shape}")
        if joined.data.shape[0] < max(o + v for o, v in zip(offsets, sizes)):
            raise SystemExit("Joined PLE tensor has fewer rows than the metadata requires")
        operation = "split"
        ple_size = joined.n_bytes
    elif per_head:
        if len(per_head) != 16 or len(set(per_head)) != 16:
            raise SystemExit("Source is missing one or more split PLE heads")
        operation = "join"
        ple_size = sum(t.n_bytes for t in tensors if HEAD_RE.fullmatch(t.name))
    else:
        raise SystemExit(f"Neither {JOINED} nor split PLE heads found")

    if args.expect_operation != "auto" and args.expect_operation != operation:
        raise SystemExit(f"Expected {args.expect_operation} operation, detected {operation}")
    logger.info("PLE preflight: OK, %s, %d tensors, %d heads, PLE %.2f GiB",
                operation, len(tensors), len(offsets), ple_size / 2**30)
    if args.check_only:
        logger.info("CHECK ONLY: no GGUF output was created")
        return

    writer = gguf.GGUFWriter(args.output, arch=architecture,
                            endianess=first.endianess)
    if operation == "split":
        split(readers, writer)
    else:
        join(readers, writer)
    logger.info("wrote %s", args.output)


if __name__ == "__main__":
    main()
