"""Validate a joined-to-per-head conversion made by the user's llama.cpp fork."""
import argparse
import hashlib
import re
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--llama-root', required=True, type=Path)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--verify-bytes', action='store_true')
    args = parser.parse_args()
    sys.path.insert(0, str(args.llama_root / 'gguf-py'))
    import gguf

    paths = [args.input]
    match = re.fullmatch(r'(.*)-(\d{5})-of-(\d{5})\.gguf', args.input.name)
    if match:
        paths = [args.input.with_name(f'{match[1]}-{i:05d}-of-{int(match[3]):05d}.gguf')
                 for i in range(1, int(match[3]) + 1)]
    readers = [gguf.GGUFReader(path, 'r') for path in paths]
    output = gguf.GGUFReader(args.output, 'r')
    source = {tensor.name: tensor for reader in readers for tensor in reader.tensors}
    dest = {tensor.name: tensor for tensor in output.tensors}
    if len(source) != sum(len(reader.tensors) for reader in readers) or len(dest) != len(output.tensors):
        raise ValueError('Duplicate tensor name')
    fields = readers[0].fields
    if fields['general.architecture'].contents() != 'qwen4exp':
        raise ValueError('Expected qwen4exp')
    for name, field in fields.items():
        if name.startswith(('GGUF.', 'split.')):
            continue
        if name not in output.fields or output.fields[name].contents() != field.contents():
            raise ValueError(f'Metadata mismatch: {name}')
    offsets = fields['qwen4exp.ple.head_offsets'].contents()
    sizes = fields['qwen4exp.ple.head_vocab_sizes'].contents()
    if len(offsets) != 16 or len(sizes) != 16:
        raise ValueError('Expected 16 n-gram heads')
    joined = source.pop('per_layer_token_embd.weight')
    if int(joined.shape[0]) != 160:
        raise ValueError('Expected 160 columns in the joined table')
    expected_names = set(source) | {f'ple_ngram_embd.{i}.weight' for i in range(16)}
    if set(dest) != expected_names:
        raise ValueError('Output tensor names do not match the expected split layout')

    def digest(data):
        raw = memoryview(data).cast('B')
        result = hashlib.sha256()
        for offset in range(0, len(raw), 8 * 1024 * 1024):
            result.update(raw[offset:offset + 8 * 1024 * 1024])
        return result.digest()

    def check(name, data, qtype):
        tensor = dest[name]
        if tensor.tensor_type != qtype or tensor.data.shape != data.shape:
            raise ValueError(f'Type/shape mismatch: {name}')
        if args.verify_bytes and digest(tensor.data) != digest(data):
            raise ValueError(f'Byte mismatch: {name}')

    for name, tensor in source.items():
        check(name, tensor.data, tensor.tensor_type)
    for index, (offset, count) in enumerate(zip(offsets, sizes)):
        check(f'ple_ngram_embd.{index}.weight', joined.data[int(offset):int(offset) + int(count)], joined.tensor_type)
    level = 'metadata, layout and all tensor payloads (SHA-256)' if args.verify_bytes else 'metadata, tensor types and layout'
    print(f'PASS: {level}; 16 heads, {len(dest)} tensors. Quantization: {joined.tensor_type.name}.')


if __name__ == '__main__':
    main()
