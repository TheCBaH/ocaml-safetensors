#!/usr/bin/env python3
"""Compare all OCaml access paths with the upstream Rust-backed raw-byte API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import struct
import subprocess
import tempfile
import safetensors
from safetensors import deserialize, safe_open
from fetch_fixtures import ROOT, LOCK, load_lock, fixture_path, verify

EXE = ROOT / '_build/default/test/conformance.exe'
REPORTS = ROOT / '.cache/reports'


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (10, 10))


def ocaml(path):
    result = subprocess.run([str(EXE), str(path)], capture_output=True, timeout=15, check=True, preexec_fn=limits)
    return json.loads(result.stdout)


def compare(path):
    data = path.read_bytes()
    expected = {name: info for name, info in deserialize(data)}
    with safe_open(str(path), framework='np') as f:
        metadata = f.metadata() or {}
    actual = ocaml(path)
    assert actual['ok'], (path.name, actual)
    assert actual['metadata'] == metadata, (path.name, 'metadata')
    got = {t['name']: t for t in actual['tensors']}
    assert len(got) == len(actual['tensors']) and got.keys() == expected.keys(), (path.name, 'names')
    header_size = struct.unpack('<Q', data[:8])[0]
    assert actual['data_start'] == header_size + 8
    header = json.loads(data[8:8+header_size])
    summaries = []
    for name, ref in sorted(expected.items()):
        t = got[name]
        assert t['dtype'] == ref['dtype'], (name, 'dtype')
        assert t['shape'] == ref['shape'], (name, 'shape')
        assert bytes.fromhex(t['data']) == bytes(ref['data']), (name, 'bytes')
        assert t['data_offsets'] == header[name]['data_offsets'], (name, 'offsets')
        summaries.append({'name': name, 'dtype': ref['dtype'], 'shape': ref['shape'],
                          'byte_length': len(ref['data']), 'sha256': hashlib.sha256(ref['data']).hexdigest()})
    return {'file': path.name, 'sha256': hashlib.sha256(data).hexdigest(), 'metadata': metadata,
            'tensor_count': len(expected), 'tensors': summaries}


def raw(header, payload=b''):
    if isinstance(header, str):
        header = header.encode()
    return struct.pack('<Q', len(header)) + header + payload


def probe_cases():
    tensor = '{"dtype":"U8","shape":[0],"data_offsets":[0,0]}'
    def t(shape='[0]', offsets='[0,0]', dtype='U8'):
        return '{"x":{"dtype":"%s","shape":%s,"data_offsets":%s}}' % (dtype, shape, offsets)
    # expected reference acceptance, expected OCaml kind (None means success), rationale
    cases = [
        ('whitespace', raw(' \t{}\r\n'), True, None, None),
        ('empty', raw('{}'), True, None, None),
        ('scalar', raw(t('[]', '[0,1]'), b'x'), True, None, None),
        ('zero-shape', raw(t('[2,0,3]')), True, None, None),
        ('duplicate-root', raw('{"x":'+tensor+',"x":'+tensor+'}'), True, 'duplicate_member', 'strict duplicate policy'),
        ('escaped-duplicate', raw('{"x":'+tensor+',"\\u0078":'+tensor+'}'), True, 'duplicate_member', 'strict duplicate policy'),
        ('duplicate-metadata', raw('{"__metadata__":{"k":"a","k":"b"}}'), True, 'duplicate_member', 'strict duplicate policy'),
        ('duplicate-field', raw('{"x":{"dtype":"U8","dtype":"U8","shape":[0],"data_offsets":[0,0]}}'), False, 'duplicate_member', None),
        ('unknown-field', raw(t().replace('"dtype"', '"extra":"ignored","dtype"')), True, 'invalid_header', 'strict unknown-field policy'),
        ('fraction', raw(t('[0.0]')), False, 'invalid_integer', None),
        ('exponent', raw(t('[0e0]')), False, 'invalid_integer', None),
        ('negative-zero', raw(t('[-0]')), False, 'invalid_integer', None),
        ('integer-string', raw(t('["0"]')), False, 'invalid_json', None),
        ('large-exact', raw(t('[9007199254740993,0]')), True, None, None),
        ('unsigned-dimension', raw(t('[9223372036854775808,0]')), True, 'resource_limit', 'signed int64 implementation limit'),
        ('empty-product-overflow', raw(t('[9223372036854775807,3,0]')), False, None, 'zero dimensions recognized before multiplication'),
        ('unsupported-fp8', raw(t('[0]', '[0,0]', 'F8_E4M3')), True, 'unsupported_dtype', 'declared dtype subset'),
        ('metadata-type', raw('{"__metadata__":{"k":1}}'), False, 'invalid_json', None),
        ('trailing-data', raw('{}', b'x'), False, 'size_mismatch', None),
        ('short-prefix', b'123', False, 'truncated', None),
        ('huge-prefix', b'\xff'*8, False, 'resource_limit', None),
        ('shape-size', raw(t('[1]')), False, 'size_mismatch', None),
        ('overlap', raw('{"a":{"dtype":"U8","shape":[1],"data_offsets":[0,1]},"b":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}', b'x'), False, 'invalid_offsets', None),
        ('gap', raw(t('[1]', '[1,2]'), b'xy'), False, 'invalid_offsets', None),
        ('deep-nesting', raw('{"x":{"shape":'+ '['*10000 + '0' + ']'*10000 + '}}'), False, 'invalid_json', None),
        ('bounded-rank', raw(t('['+','.join(['0']*1000)+']')), True, 'resource_limit', 'configured rank limit'),
    ]
    return cases


def probes():
    output = []
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'probe.safetensors'
        for name, data, exp_ref, exp_kind, reason in probe_cases():
            path.write_bytes(data)
            try:
                deserialize(data)
                reference = True
            except safetensors.SafetensorError:
                reference = False
            actual = ocaml(path)
            observed = None if actual['ok'] else actual['kind']
            row = {'case': name, 'reference_accepts': reference, 'ocaml_accepts': actual['ok'],
                   'ocaml_error': observed, 'difference_reason': reason}
            output.append(row)
            print(json.dumps(row), flush=True)
            assert reference == exp_ref, (name, 'reference expectation changed', reference)
            assert observed == exp_kind, (name, 'OCaml expectation changed', actual)
            assert reference == actual['ok'] or reason is not None, (name, 'unexplained difference')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=['synthetic', 'hub'])
    args = parser.parse_args()
    assert safetensors.__version__ == '0.8.0'
    REPORTS.mkdir(parents=True, exist_ok=True)
    report = {'suite': args.suite, 'reference_version': safetensors.__version__,
              'python': platform.python_version(), 'platform': platform.platform(),
              'reader_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
              'fixture_lock_sha256': hashlib.sha256(LOCK.read_bytes()).hexdigest(),
              'reference_requirements_sha256': hashlib.sha256((ROOT/'scripts/reference-requirements.txt').read_bytes()).hexdigest(),
              'files': []}
    if args.suite == 'synthetic':
        report['compatibility'] = probes()
        manifest = json.loads((ROOT/'test/fixtures/manifest.json').read_text())
        for name, entry in manifest['files'].items():
            path = ROOT/'test/fixtures'/name
            verify(path, {'id': name, **entry})
            report['files'].append(compare(path))
    else:
        lock = load_lock()
        for entry in lock['files']:
            path = fixture_path(entry)
            verify(path, entry)
            result = compare(path)
            assert result['tensor_count'] == entry['tensor_count']
            report['files'].append(result)
    target = REPORTS/(args.suite+'.json')
    target.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(f"{args.suite}: {len(report['files'])} files, {sum(f['tensor_count'] for f in report['files'])} tensors, all access paths byte-exact; {target}")


if __name__ == '__main__':
    main()
