#!/usr/bin/env python3
"""Compare numeric Draft attention K/V from MTP seq-state snapshots.

The snapshots are created by llama_state_seq_save_file(ctx_dft, seq=0, tokens=[]).
This reader intentionally parses only the FIRST (attention) KV section of the
hybrid-memory state: subsequent recurrent/indexer bytes are not treated as KV.
Supports GGML F32/F16 K/V (including transposed V) and aligns logical token
positions/seq IDs, not physical cache-slot offsets.

Usage:
  python tools/evox2/benchmark/analyze_mtp_kv_parity.py \
    --directory kv-parity-output/short --left C --right A --report short-C-A.json
"""
from __future__ import annotations

import argparse
import json
import mmap
import re
import struct
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


@dataclass(frozen=True)
class Block:
    dtype: int
    offset: int
    count: int
    row_bytes: int
    transposed: bool = False

    @property
    def width(self) -> int:
        return self.row_bytes // (2 if self.dtype == 1 else 4)


@dataclass(frozen=True)
class Snapshot:
    magic: int
    version: int
    path: str
    positions: tuple[int, ...]
    seq_ids: tuple[tuple[int, ...], ...]
    v_trans: bool
    n_rot_k: int
    n_rot_v: int
    keys: tuple[Block, ...]
    values: tuple[Block, ...]


def _u32(data: mmap.mmap, off: int) -> int:
    if off + 4 > len(data):
        raise ValueError("truncated u32")
    return struct.unpack_from("<I", data, off)[0]


def _i32(data: mmap.mmap, off: int) -> int:
    if off + 4 > len(data):
        raise ValueError("truncated i32")
    return struct.unpack_from("<i", data, off)[0]


def _u64(data: mmap.mmap, off: int) -> int:
    if off + 8 > len(data):
        raise ValueError("truncated u64")
    return struct.unpack_from("<Q", data, off)[0]


def _parse_attention(data: mmap.mmap, path: str, ext_bytes: int) -> Snapshot:
    if len(data) < 24:
        raise ValueError("snapshot too small")
    magic, version, n_tokens = struct.unpack_from("<III", data, 0)
    if n_tokens != 0 or version == 0:
        raise ValueError("not an expected zero-token llama seq-state file")
    off = 12
    n_stream = _u32(data, off)
    off += 4
    if n_stream != 1:
        raise ValueError(f"single-stream Draft only, got n_stream={n_stream}")
    n_cells = _u32(data, off)
    off += 4
    if not (1 <= n_cells <= 1000000):
        raise ValueError(f"bad attention cell count: {n_cells}")

    positions: list[int] = []
    seq_ids: list[tuple[int, ...]] = []
    for _ in range(n_cells):
        pos = _i32(data, off)
        nseq = _u32(data, off + 4)
        if pos < 0 or nseq < 1 or nseq > 64:
            raise ValueError("invalid cell position or sequence count")
        off += 8 + ext_bytes
        if off + 4 * nseq > len(data):
            raise ValueError("truncated seq cell metadata")
        ids = tuple(_i32(data, off + 4 * i) for i in range(nseq))
        if any(x < 0 for x in ids):
            raise ValueError("invalid cell sequence id")
        off += 4 * nseq
        positions.append(pos)
        seq_ids.append(ids)
    if len(set(positions)) != len(positions):
        raise ValueError("duplicate logical positions: unsupported")
    v_trans, n_layer, n_rot_k, n_rot_v = struct.unpack_from("<IIII", data, off)
    off += 16
    if v_trans not in (0, 1) or not (1 <= n_layer <= 128):
        raise ValueError(f"invalid attention data header v_trans={v_trans} layers={n_layer}")
    if n_rot_k > 4096 or n_rot_v > 4096:
        raise ValueError("invalid rotary layout")

    def read_block(transposed: bool) -> Block:
        nonlocal off
        dtype = _i32(data, off)
        off += 4
        if dtype not in (0, 1):  # GGML_TYPE_F32 / GGML_TYPE_F16
            raise ValueError(f"unsupported KV dtype {dtype}; requires f16/f32")
        element_bytes = 4 if dtype == 0 else 2
        if transposed:
            elem_size = _u32(data, off)
            width = _u32(data, off + 4)
            off += 8
            if elem_size != element_bytes or not (1 <= width <= 16384):
                raise ValueError("invalid transposed V layout")
            row_bytes = width * element_bytes
        else:
            row_bytes = _u64(data, off)
            off += 8
            if not (element_bytes <= row_bytes <= 16384 * element_bytes) or row_bytes % element_bytes:
                raise ValueError("invalid KV row width")
        total = n_cells * row_bytes
        if off + total > len(data):
            raise ValueError("truncated KV tensor bytes")
        block = Block(dtype, off, n_cells, row_bytes, transposed)
        off += total
        return block

    keys = tuple(read_block(False) for _ in range(n_layer))
    vals = tuple(read_block(bool(v_trans)) for _ in range(n_layer))
    if off >= len(data):
        raise ValueError("no trailing recurrent state; incompatible memory layout")
    return Snapshot(magic, version, path, tuple(positions), tuple(seq_ids),
                    bool(v_trans), n_rot_k, n_rot_v, keys, vals)


def parse_snapshot(data: mmap.mmap, path: str, ext_bytes: int | None = None) -> Snapshot:
    # Qwen PLE uses ggml-kv-cell-ext (x,y,tok: 3 x int32), some MTP
    # sidecars do not. Guess conservatively and require exactly one parse.
    candidates = [ext_bytes] if ext_bytes is not None else [0, 12]
    valid = []
    for ext in candidates:
        try:
            valid.append((ext, _parse_attention(data, path, ext)))
        except (ValueError, struct.error):
            pass
    if len(valid) != 1:
        raise ValueError(f"{path}: ambiguous/incompatible attention header; "
                         f"ext candidates passing={ [x[0] for x in valid] }; "
                         "specify --cell-ext-bytes 0 or 12 or audit serialization")
    return valid[0][1]


@contextmanager
def mapped_file(path: Path) -> Iterator[mmap.mmap]:
    with path.open("rb") as file:
        with mmap.mmap(file.fileno(), length=0, access=mmap.ACCESS_READ) as mm:
            yield mm


def _numpy_view(np: Any, data: mmap.mmap, block: Block) -> Any:
    dtype = "<f2" if block.dtype == 1 else "<f4"
    ar = np.frombuffer(data, dtype=dtype, count=block.count * block.width,
                       offset=block.offset)
    if block.transposed:
        return ar.reshape(block.width, block.count).T
    return ar.reshape(block.count, block.width)


def compare(left: Path, right: Path, *, atol: float = 1e-3, rtol: float = 1e-3,
            cell_ext_bytes: int | None = None, chunk_rows: int = 256) -> dict:
    try:
        import numpy as np
    except ImportError as ex:
        raise RuntimeError("numpy is required for numerical KV comparison (python -m pip install numpy)") from ex

    report: dict[str, Any] = {"left": str(left), "right": str(right),
        "atol": atol, "rtol": rtol, "status": "FAIL", "layers": []}
    with mapped_file(left) as ml, mapped_file(right) as mr:
        a = parse_snapshot(ml, str(left), cell_ext_bytes)
        b = parse_snapshot(mr, str(right), cell_ext_bytes)

        props = ("magic", "version", "v_trans", "n_rot_k", "n_rot_v")
        for prop in props:
            if getattr(a, prop) != getattr(b, prop):
                raise ValueError(f"state header mismatch {prop}: {getattr(a, prop)} vs {getattr(b, prop)}")
        if len(a.keys) != len(b.keys):
            raise ValueError("attention layer count mismatch")
        posa = {p: i for i, p in enumerate(a.positions)}
        posb = {p: i for i, p in enumerate(b.positions)}
        if set(posa) != set(posb):
            missing = sorted(set(posa) - set(posb))
            extra = sorted(set(posb) - set(posa))
            raise ValueError(f"KV token position mismatch: A-only={missing[:10]}, B-only={extra[:10]}")
        common = sorted(posa)
        if any(a.seq_ids[posa[p]] != b.seq_ids[posb[p]] for p in common):
            raise ValueError("KV seq_id mapping mismatch")
        report.update({"position_count": len(common), "position_min": min(common),
                       "position_max": max(common), "attention_layers": len(a.keys),
                       "v_trans": a.v_trans, "cell_ext_bytes": cell_ext_bytes})
        ok = True
        for kind, aa, bb in (("K", a.keys, b.keys), ("V", a.values, b.values)):
            for layer, (ba, bb0) in enumerate(zip(aa, bb)):
                if (ba.dtype, ba.width) != (bb0.dtype, bb0.width):
                    raise ValueError(f"{kind} layer{layer} dtype/width mismatch")
                va = _numpy_view(np, ml, ba)
                vb = _numpy_view(np, mr, bb0)
                checked = bit_different = beyond = nonfinite = 0
                max_abs = max_rel = 0.0
                for start in range(0, len(common), chunk_rows):
                    part = common[start:start + chunk_rows]
                    idxa = [posa[p] for p in part]
                    idxb = [posb[p] for p in part]
                    x = va[idxa].astype(np.float32)
                    y = vb[idxb].astype(np.float32)
                    checked += x.size
                    nonfinite += int(np.count_nonzero(~np.isfinite(x) | ~np.isfinite(y)))
                    # Bitwise count catches signed zeros etc separately from tolerance.
                    bits_dtype = np.uint16 if ba.dtype == 1 else np.uint32
                    bit_different += int(np.count_nonzero(x.astype(va.dtype).view(bits_dtype) !=
                                                           y.astype(vb.dtype).view(bits_dtype)))
                    dif = np.abs(x - y)
                    finite = np.isfinite(dif)
                    if finite.any():
                        max_abs = max(max_abs, float(np.max(dif[finite])))
                        denom = np.maximum(np.abs(x), 1e-6)
                        max_rel = max(max_rel, float(np.max((dif / denom)[finite])))
                    beyond += int(np.count_nonzero(~finite | (dif > atol + rtol * np.abs(x))))
                valid = beyond == 0 and nonfinite == 0
                ok &= valid
                report["layers"].append({
                    "kind": kind, "layer": layer, "dtype": "f16" if ba.dtype == 1 else "f32",
                    "width": ba.width, "values_checked": checked,
                    "bitwise_different": bit_different, "outside_tolerance": beyond,
                    "nonfinite_values": nonfinite, "max_abs": max_abs, "max_relative": max_rel,
                    "pass": bool(valid),
                })
        report["status"] = "PASS" if ok else "FAIL"
        return report


def find_one(directory: Path, tag: str, threshold: int) -> Path:
    files = sorted(directory.glob(f"draft-kv-{tag}-threshold-{threshold}-pos-*.bin"))
    if len(files) != 1:
        raise ValueError(f"expected exactly one {tag} threshold {threshold} snapshot in {directory}; got {len(files)}")
    return files[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--left", choices=("C", "A", "B"), required=True)
    parser.add_argument("--right", choices=("C", "A", "B"), required=True)
    parser.add_argument("--threshold", type=int, required=True)
    parser.add_argument("--cell-ext-bytes", type=int, choices=(0, 12))
    parser.add_argument("--atol", type=float, default=0.001)
    parser.add_argument("--rtol", type=float, default=0.001)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.left == args.right or args.atol < 0 or args.rtol < 0:
        parser.error("different arms and nonnegative tolerances are required")
    try:
        left = find_one(args.directory, args.left, args.threshold)
        right = find_one(args.directory, args.right, args.threshold)
        result = compare(left, right, atol=args.atol, rtol=args.rtol,
                         cell_ext_bytes=args.cell_ext_bytes)
    except (OSError, ValueError, RuntimeError) as ex:
        result = {"status": "ERROR", "error": str(ex)}
    result["arms"] = f"{args.left}/{args.right}"
    result["threshold"] = args.threshold
    text = json.dumps(result, ensure_ascii=False, indent=2)
    print(text)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    return 0 if result["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
