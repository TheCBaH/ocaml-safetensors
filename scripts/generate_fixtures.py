#!/usr/bin/env python3
"""Reproduce the small, project-owned offline fixtures with the pinned writer."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import numpy as np
import safetensors
from safetensors.numpy import save

ROOT = Path(__file__).resolve().parents[1]


def raw(header, payload=b''):
    if isinstance(header, dict):
        header = json.dumps(header, ensure_ascii=False, separators=(',', ':')).encode()
    return struct.pack('<Q', len(header)) + header + payload


def generate():
    assert safetensors.__version__ == '0.8.0'
    assert np.__version__ == '2.2.6'
    arrays = {}
    for dtype in ('bool', 'uint8', 'int8', 'uint16', 'int16', 'uint32', 'int32',
                  'uint64', 'int64', 'float16', 'float32', 'float64'):
        if dtype.startswith('float'):
            values = [0., -0., float('inf'), -float('inf'), float('nan'), 1.5]
        elif dtype == 'bool':
            values = [False, True, True, False, False, True]
        else:
            values = range(6)
        arrays['tensor.' + dtype] = np.array(values, dtype=dtype).reshape(2, 3)
    arrays['scalar.é'] = np.array(-42, dtype='int64')
    arrays['empty'] = np.empty((2, 0, 3), dtype='float32')
    bf16 = struct.pack('<8H', 0, 0x8000, 0x3f80, 0xbf80, 0x7f80, 0xff80, 0x7fc1, 1)
    return {
        'numpy-all.safetensors': save(arrays, metadata={'unicode': '☃'}),
        'bf16.safetensors': raw({'bits': {'dtype': 'BF16', 'shape': [8], 'data_offsets': [0, 16]}}, bf16),
        'layout.safetensors': raw(b'\t {"z":{"dtype":"U8","shape":[1],"data_offsets":[0,1]},"a":{"dtype":"U8","shape":[0],"data_offsets":[0,0]},"b":{"dtype":"U8","shape":[0],"data_offsets":[1,1]}}\n ', b'\xa5'),
        'empty.safetensors': raw({}),
        'metadata.safetensors': raw({'__metadata__': {'description': 'no tensors', '': 'empty key'}}),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    directory = ROOT / 'test' / 'fixtures'
    fixtures = generate()
    manifest = {'generator': 'scripts/generate_fixtures.py', 'safetensors': safetensors.__version__,
                'numpy': np.__version__, 'license': 'MIT', 'files': {}}
    for name, data in sorted(fixtures.items()):
        manifest['files'][name] = {'size_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        if args.write:
            directory.mkdir(parents=True, exist_ok=True)
            (directory / name).write_bytes(data)
        else:
            assert (directory / name).read_bytes() == data, f'{name}: regeneration drift'
    encoded = json.dumps(manifest, indent=2, sort_keys=True) + '\n'
    if args.write:
        (directory / 'manifest.json').write_text(encoded)
    else:
        assert (directory / 'manifest.json').read_text() == encoded, 'manifest drift'
    print('synthetic fixtures:', len(fixtures), 'files,', sum(map(len, fixtures.values())), 'bytes')


if __name__ == '__main__':
    main()
