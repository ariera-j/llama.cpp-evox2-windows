"""Fixed HIP-2 fixtures. Enumeration and reference modes use only the Python standard library."""
import argparse
import csv
import hashlib
import math
import os
import re
from pathlib import Path
import struct
from typing import NamedTuple


class Case(NamedTuple):
    id: str
    op: str
    k: int
    m: int
    e: int
    t: int
    s: int
    b: int
    padding: int
    gap: int
    offset: int
    pitch: int
    sgemms: int


SCHED_FIXTURES = {'S-HC-CPU': '6', 'S-HC-PIN': '6', 'S-ID-PIN': '8'}


def catalog():
    rows = []
    for line in Path(__file__).with_name('cases.inc').read_text().splitlines():
        if line.startswith('CASE(') and line.endswith(')'):
            fields = next(csv.reader([line[5:-1]], skipinitialspace=True))
            rows.append(Case(*fields[:2], *map(int, fields[2:])))
    if [c.id for c in rows] != ['1', '1-NC', '2', '2-C', '5', '6', '7', '8', '9', '9-Z', *SCHED_FIXTURES]:
        raise ValueError('unexpected case catalog')
    records = '\n'.join(line for line in Path(__file__).with_name('cases.inc').read_text().splitlines() if line.startswith('CASE('))
    if hashlib.sha256('\n'.join(records.splitlines()[:10]).encode()).hexdigest() != '0f5c1cf6b166d57f6c8ed16bc85c3ef6d8a88f10837c09d55655dfd577c6feea':
        raise ValueError('operation, shape or layout differs from reviewed enumeration')
    if hashlib.sha256(records.encode()).hexdigest() != '5afb7000d94c9bcadba08336d2f4ba3c018a32d36dda53dd8595e7d8cf4b0136':
        raise ValueError('unexpected scheduler catalog')
    return rows


def decode(scale, code):
    exponent, mantissa = divmod(scale, 8)
    d = 0.0 if scale > 126 else mantissa/1024 if not exponent else math.ldexp(8 + mantissa, exponent - 11)
    return d * (0, 1, 2, 3, 4, 6, 8, 10, 0, -1, -2, -3, -4, -6, -8, -10)[code]


def check_codec_tables():
    path = Path(__file__).resolve().parents[3] / 'ggml/rocmfp4/rocmfp4.c'
    source = path.read_text(encoding='utf-8')
    codes = source.split('rocmfp4_codebook[16] = {')[1].split('};')[0]
    table = source.split('rocmfp4_scale_ue4m3_half[127] = {')[1].split('};')[0]
    signed = list(map(int, re.findall(r'-?\d+', codes)))
    entries = re.findall(r'ROCMFP4_SCALE_(SUB|E\d+)\((\d)\)', table)
    if len(entries) != 127 or len(signed) != 16:
        raise ValueError('unexpected product codec tables')
    for b in range(256):
        scale = 0.0
        if b < len(entries):
            name, digit = entries[b]
            macro = re.search(r'^#define ROCMFP4_SCALE_' + name + r'\(M\) (.+)$', source, re.M)[1]
            exponent = int(re.search(r'0x1p(-?\d+)f', macro)[1])
            scale = math.ldexp(int(digit) + (8 if '(8 +' in macro else 0), exponent)
        for q, value in enumerate(signed):
            if struct.pack('<f', value*scale) != struct.pack('<f', decode(b, q)):
                raise ValueError(('product codec', b, q))


def fixture(c):
    c = c._replace(id=SCHED_FIXTURES.get(c.id, c.id))
    converting = c.op.startswith('F')
    row = c.k//32 + c.padding
    expert = row*c.m + c.gap
    packed = bytearray([0xdf]) * (17*(c.offset + c.e*expert + 1))
    for e in range(c.e):
        for m in range(c.m):
            for block in range(c.k//32):
                start = 17*(c.offset + e*expert + m*row + block)
                phase = 0 if converting else (e*3 + m + block) % 16
                for j in range(16):
                    low = (j + phase) % 16
                    packed[start + j] = low | ((15 - low) << 4)
                packed[start + 16] = (m + block) % 256 if converting else 48 + (e*7 + m + block) % 24

    def weight(e, m, j):
        block, q = divmod(j, 32)
        start = 17*(c.offset + e*expert + m*row + block)
        code = (packed[start + q % 16] >> (4*(q//16))) & 15
        return decode(packed[start + 16], code)

    if converting:
        fmt = '<e' if c.op.startswith('F16') else '<f'
        expected = b''.join(struct.pack(fmt, weight(0, m, j)) for m in range(c.m) for j in range(c.k))
        return bytes(packed), [], [], expected, []

    active = {'7': [3, 1], '8': [2, 0, 0, 2, 2, 2], '9': [2, 0, 1, 2, 1, -1, 2, 0, 0, 2]}.get(c.id, [])
    if c.id == '9-Z':
        active = [-1]*(c.s*c.t)
    indices = [-99]*(c.pitch*c.t)
    for n, value in enumerate(active):
        t, s = divmod(n, c.s)
        if not -1 <= value < c.e:
            raise ValueError('invalid active expert')
        indices[t*c.pitch + s] = value
    x = []
    for r in range(c.b*c.t):
        for j in range(c.k):
            v = float(j == 21) if c.id == '5' else (-1)**j * (1 + (j*7 + r*11) % 29) / 13
            if c.id == '6' and r < 2:
                # Row 0 weights at columns 1 and 9 are +1/4 and -1/4.
                v = (1.0 + r*2**-23) if j == 1 else float(j == 9)
            x.append(struct.unpack('<f', struct.pack('<f', v))[0])
    ref, bound = [], []
    for t in range(c.t):
        for s in range(c.s):
            e = active[t*c.s + s] if active else 0
            start = (t*c.b + s % c.b)*c.k
            for m in range(c.m):
                products = [weight(e, m, j)*x[start+j] for j in range(c.k)] if e >= 0 else [0.0]
                ref.append(math.fsum(products))
                sab = math.fsum(map(abs, products))
                ku = c.k*2**-24
                if c.id == '6' and m == 0 and s < 2:
                    target = s*2**-25
                    if ref[-1] != target or not (min(products) < 0 < max(products)):
                        raise ValueError('missing cancellation witness')
                bound.append(0 if e == -1 or c.id == '5' else 2*ku/(1-ku)*sab + 1e-7)
    if c.id == '6' and not (min(ref[2*c.m:]) < 0 < max(ref[2*c.m:])):
        raise ValueError('missing general signed outputs')
    return bytes(packed), x, indices, ref, bound


def id_span(slots, tokens, slot_stride, pitch, offset, root_bytes, allocation):
    if min(slots, tokens) <= 0 or slot_stride != 4 or pitch < slots*4 or pitch % 4 or offset < 0 or offset % 4:
        raise ValueError('invalid ID layout')
    span = (tokens-1)*pitch + slots*4
    if offset + span > min(root_bytes, allocation, (1 << 64)-1):
        raise ValueError('ID view extends beyond storage')
    return span


def check_id_bounds():
    valid = (2, 3, 4, 2048, 4, 4108, 4108)
    if id_span(*valid) != 4104:
        raise ValueError('incorrect top-k span')
    for field, value in [(0, 0), (1, 0), (2, 8), (3, 4), (3, 9), (3, 1 << 63),
                         (4, 2), (4, 8), (5, 4107), (6, 4107)]:
        args = list(valid)
        args[field] = value
        try:
            id_span(*args)
        except ValueError:
            continue
        raise ValueError(('accepted invalid ID layout', args))


def check_cpu(c, data):
    packed, x, ids, ref, bounds = data
    if packed[-17:] != bytes([0xdf])*17 or len(ref) == 0:
        raise ValueError('guard or output size')
    if c.op.startswith('F'):
        fmt = '<e' if c.op.startswith('F16') else '<f'
        # Independent integer arithmetic in units of 2^-10; keep the sign of a zero product.
        mags = (0, 1, 2, 3, 4, 6, 8, 10)
        expected = bytearray()
        for m in range(c.m):
            for b in range(c.k//32):
                scale = (m+b) % 256
                exp, frac = divmod(scale, 8)
                units = 0 if scale >= 127 else frac if exp == 0 else (8+frac) << (exp-1)
                for q in [*range(16), *reversed(range(16))]:
                    value = units*mags[q % 8]/1024
                    expected.extend(struct.pack(fmt, -value if q > 8 else value))
        if expected != ref:
            raise ValueError('decoder bits including signed zero')
    else:
        if len(x) != c.k*c.b*c.t or len(ref) != c.m*c.s*c.t or not all(map(math.isfinite, ref + bounds)):
            raise ValueError('invalid reference')
        if c.id in ('S-HC-CPU', 'S-HC-PIN'):
            # Decode whole rows and sum exact binary rationals independently of the FP64 dot loop.
            from fractions import Fraction
            for m in range(c.m):
                weights = []
                for b in range(c.k//32):
                    start = 17*(c.offset + m*(c.k//32 + c.padding) + b)
                    block = packed[start:start+17]
                    codes = [a & 15 for a in block[:16]] + [a >> 4 for a in block[:16]]
                    weights.extend(Fraction(decode(block[16], q)) for q in codes)
                for r in range(c.b):
                    terms = [w*v for w, v in zip(weights, map(Fraction, x[r*c.k:(r+1)*c.k]))]
                    if float(sum(terms)) != ref[r*c.m+m]:
                        raise ValueError('independent dense dot mismatch')
        if c.pitch:
            id_span(c.s, c.t, 4, c.pitch*4, 0, len(ids)*4, len(ids)*4)
            # Reconstruct the synchronized grouping and reverse scatter independently of direct slot lookup.
            active = [ids[t*c.pitch+s] for t in range(c.t) for s in range(c.s)]
            for slot, e in enumerate(active):
                if e == -1:
                    begin = slot*c.m
                    if any(ref[j] != 0.0 or bounds[j] != 0.0 for j in range(begin, begin+c.m)):
                        raise ValueError('skipped slot reference')
            if len({e for e in active if e >= 0}) != c.sgemms:
                raise ValueError('expected SGEMM count')
            pairs = [(t, s) for e in range(c.e) for t in range(c.t) for s in range(c.s) if ids[t*c.pitch+s] == e]
            if len(set(pairs)) != len(pairs) or len(pairs) + ids.count(-1) != c.s*c.t:
                raise ValueError('grouping cardinality')
            result = [0.0]*len(ref)
            for t, s in pairs:
                e = ids[t*c.pitch+s]
                stride = c.k//32 + c.padding
                start = (t*c.b + s%c.b)*c.k
                for m in range(c.m):
                    pos = 17*(c.offset + e*(stride*c.m+c.gap) + m*stride)
                    decoded = []
                    for j in range(0, c.k, 32):
                        block = packed[pos:pos+17]
                        codes = [a & 15 for a in block[:16]] + [a >> 4 for a in block[:16]]
                        decoded.extend(decode(block[-1], a) for a in codes)
                        pos += 17
                    result[(t*c.s+s)*c.m+m] = math.fsum(a*b for a, b in zip(decoded, x[start:start+c.k]))
            if result != ref:
                raise ValueError('scatter mismatch')


def gpu(c, data, path):
    import ctypes as ct
    packed, x, ids, ref, bounds = data
    output_bytes = len(ref) if isinstance(ref, bytes) else 4*len(ref)
    path = path.resolve(strict=True)
    with os.add_dll_directory(str(path.parent)):
        dll = ct.CDLL(str(path))
        reg_args = []
        if c.id in SCHED_FIXTURES:
            registry = ct.CDLL(str(path.with_name('ggml.dll').resolve(strict=True)))
            registry.ggml_backend_load.argtypes = [ct.c_char_p]
            registry.ggml_backend_load.restype = ct.c_void_p
            cpu_path = path.with_name('ggml-cpu.dll').resolve(strict=True)
            cpu = registry.ggml_backend_load(os.fsencode(cpu_path))
            if not cpu:
                raise RuntimeError('CPU backend registration failed')
            reg_args.append(cpu)
            run = dll.evox2_hip2e_sched_case
        else:
            run = dll.evox2_hip2a_case
        run.argtypes = [ct.c_void_p]*len(reg_args) + [ct.c_char_p, ct.c_char_p, ct.c_void_p, ct.c_void_p, ct.c_size_t, ct.c_void_p, ct.c_size_t,
                        ct.c_void_p, ct.c_size_t, ct.c_void_p, ct.c_size_t]
        run.restype = ct.c_int
        out = ct.create_string_buffer(output_bytes)
        geometry = (ct.c_int*10)(*c[2:-1])
        done = run(*reg_args, c.id.encode(), c.op.encode(), geometry, packed, len(packed), (ct.c_float*len(x))(*x), len(x),
                   (ct.c_int32*len(ids))(*ids), len(ids), out, output_bytes)
        if done != 1:
            raise RuntimeError('expected one executed case')
    if isinstance(ref, bytes):
        if out.raw != ref:
            raise ValueError('GPU decoder bits')
    else:
        values = struct.unpack(f'<{len(ref)}f', out.raw)
        relative, condition = [], []
        for i, (v, gold, a) in enumerate(zip(values, ref, bounds)):
            if c.pitch:
                token, slot = divmod(i//c.m, c.s)
                if ids[token*c.pitch + slot] == -1 and out.raw[4*i:4*i+4] != bytes(4):
                    raise ValueError(('skipped slot must contain positive zero', token, slot, i))
            if not math.isfinite(v) or abs(v-gold) > a:
                raise ValueError((i, v, gold, a))
            if abs(gold) > 1e-6 and c.id != '5':
                relative.append(abs(v-gold)/abs(gold))
                ku = c.k*2**-24
                condition.append((a-1e-7)*(1-ku)/(2*ku*abs(gold)))
        if relative:
            print('max relative error', max(relative), 'max condition', max(condition))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['enumerate', 'reference', 'gpu'])
    parser.add_argument('--case', choices=[c.id for c in catalog()])
    parser.add_argument('--dll', type=Path)
    args = parser.parse_args()
    if args.mode == 'gpu' and (not args.case or not args.dll or os.name != 'nt'):
        parser.error('GPU requires Windows, one exact case and an explicit test DLL')
    if args.mode == 'reference':
        check_codec_tables()
        check_id_bounds()
        print("CPU codec 4096 pairs; ID span 1 positive, 10 negative")
    for c in catalog():
        if c.id in SCHED_FIXTURES and not args.case and args.mode != 'enumerate':
            continue
        if args.case and c.id != args.case:
            continue
        print(*c, flush=True)
        if args.mode != 'enumerate':
            data = fixture(c)
            check_cpu(c, data)
            if args.mode == 'gpu':
                gpu(c, data, args.dll)
            ref = data[3]
            bits = ref if isinstance(ref, bytes) else struct.pack(f'<{len(ref)}d', *ref)
            print('PASS', c.id, 'reference SHA256', hashlib.sha256(bits).hexdigest())


if __name__ == '__main__':
    main()
