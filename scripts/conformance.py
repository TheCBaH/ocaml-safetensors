#!/usr/bin/env python3
"""Compare all OCaml access paths with the upstream Rust-backed raw-byte API."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import math
import struct
import subprocess
import tempfile
import safetensors
from safetensors import deserialize, safe_open
from fetch_fixtures import ROOT, LOCK, load_lock, fixture_path, verify
from reference_versions import assert_reference_versions
from conformance_fuzz import Recorder, mutations, unpack

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
        ('integer-string', raw(t('["0"]')), False, 'invalid_header', None),
        ('large-exact', raw(t('[9007199254740993,0]')), True, None, None),
        ('unsigned-dimension', raw(t('[9223372036854775808,0]')), True, 'invalid_integer', 'signed int64 implementation limit'),
        ('empty-product-overflow', raw(t('[9223372036854775807,3,0]')), False, None, 'zero dimensions recognized before multiplication'),
        ('supported-fp8', raw(t('[0]', '[0,0]', 'F8_E4M3')), True, None, None),
        ('metadata-type', raw('{"__metadata__":{"k":1}}'), False, 'invalid_header', None),
        ('trailing-data', raw('{}', b'x'), False, 'size_mismatch', None),
        ('short-prefix', b'123', False, 'truncated', None),
        ('huge-prefix', b'\xff'*8, False, 'invalid_integer', None),
        ('shape-size', raw(t('[1]')), False, 'size_mismatch', None),
        ('overlap', raw('{"a":{"dtype":"U8","shape":[1],"data_offsets":[0,1]},"b":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}', b'x'), False, 'invalid_offsets', None),
        ('gap', raw(t('[1]', '[1,2]'), b'xy'), False, 'invalid_offsets', None),
        ('deep-nesting', raw('{"x":{"shape":'+ '['*10000 + '0' + ']'*10000 + '}}'), False, 'invalid_header', None),
        ('bounded-rank', raw(t('['+','.join(['0']*1000)+']')), True, 'resource_limit', 'configured rank limit'),
    ]
    for dtype, width in [('F8_E5M2', 1), ('F8_E4M3', 1), ('F8_E8M0', 1),
                         ('F8_E4M3FNUZ', 1), ('F8_E5M2FNUZ', 1), ('C64', 8)]:
        payload = bytes((i * 71 + 128) % 256 for i in range(width * 2))
        cases.append(('dtype-' + dtype, raw(t('[2]', f'[0,{len(payload)}]', dtype), payload),
                      True, None, None))
    cases.append(('mixed-fp8-f32', raw(
        '{"fp8":{"dtype":"F8_E4M3","shape":[2],"data_offsets":[0,2]},'
        '"float":{"dtype":"F32","shape":[1],"data_offsets":[2,6]}}',
        b'\x80\x7f\x00\x00\x80\x3f'), True, None, None))
    return cases


def probes(recorder):
    output = []
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'probe.safetensors'
        for name, data, exp_ref, exp_kind, reason in probe_cases():
            def check_probe(value):
                result = observe(value, path)
                if result is not None:
                    return result
                if value == data:
                    candidate = ocaml(path)
                    kind = None if candidate['ok'] else candidate['kind']
                    try:
                        deserialize(value)
                        accepts = True
                    except safetensors.SafetensorError:
                        accepts = False
                    if accepts != exp_ref:
                        return 'probe-reference-' + name, {'accepts': accepts}
                    if kind != exp_kind:
                        return 'probe-kind-' + name, candidate
                return None
            recorder.check(data, check_probe, case=name, mutation='probe')
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


def record_compare(recorder, path):
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / 'fixture.safetensors'
        recorder.check(path.read_bytes(), lambda value: observe(value, probe),
                       case=path.name, mutation='fixture')
    try:
        return compare(path)
    except Exception as error:
        def failed_comparison(value):
            if value == path.read_bytes():
                return 'fixture-comparison', repr(error)
            return observe(value, probe)
        with tempfile.TemporaryDirectory() as tmp:
            probe = Path(tmp) / 'fixture.safetensors'
            recorder.check(path.read_bytes(), failed_comparison, case=path.name, mutation='fixture')
        raise


def json_path(name):
    return '$[' + json.dumps(name, ensure_ascii=False) + ']'


def policy_difference(data, reference_accepts, actual):
    """Each exception names a concrete policy and the rejecting field."""
    decoded = unpack(data)
    if not decoded:
        return None
    header, _ = decoded
    if not isinstance(header, dict):
        return None
    if reference_accepts and not actual['ok']:
        kind, path = actual['kind'], actual.get('path') or ''
        if kind == 'duplicate_member':
            class Pairs(list):
                pass
            try:
                size = struct.unpack('<Q', data[:8])[0]
                root = json.loads(data[8:8 + size], object_pairs_hook=Pairs)
            except (ValueError, UnicodeError):
                return None
            if isinstance(root, Pairs):
                seen = set()
                for key, value in root:
                    if key in seen and path == json_path(key):
                        return 'strict decoded root duplicate rejection'
                    seen.add(key)
                    if key == '__metadata__' and isinstance(value, Pairs):
                        metadata_seen = set()
                        for member, _ in value:
                            if member in metadata_seen and path == json_path(key) + '[' + json.dumps(member, ensure_ascii=False) + ']':
                                return 'strict decoded metadata duplicate rejection'
                            metadata_seen.add(member)
        for name, tensor in header.items():
            if name == '__metadata__' or not isinstance(tensor, dict):
                continue
            prefix = json_path(name)
            if kind == 'invalid_header' and any(
                    path == prefix + '[' + json.dumps(key) + ']'
                    for key in tensor if key not in {'dtype', 'shape', 'data_offsets'}):
                return 'strict unknown tensor-field rejection'
            if kind == 'unsupported_dtype' and tensor.get('dtype') in {'F4', 'F6_E2M3', 'F6_E3M2'}:
                if path == prefix + '["dtype"]':
                    return 'packed dtype deferred'
            shape = tensor.get('shape')
            if isinstance(shape, list):
                for i, dimension in enumerate(shape):
                    if (kind == 'invalid_integer' and type(dimension) is int
                            and dimension > 9223372036854775807
                            and path == prefix + f'["shape"][{i}]'):
                        return 'signed int64 dimension limit'
                if kind == 'resource_limit' and len(shape) > 64 and path.startswith(prefix + '["shape"]'):
                    return 'configured rank limit'
    if actual['ok'] and not reference_accepts:
        for tensor in header.values():
            if not isinstance(tensor, dict):
                continue
            shape = tensor.get('shape')
            if (isinstance(shape, list) and 0 in shape
                    and all(type(n) is int and 0 <= n <= 9223372036854775807 for n in shape)
                    and math.prod(n for n in shape if n) > 18446744073709551615):
                return 'zero dimensions checked before intermediate product overflow'
    return None


def observe(data, path):
    path.write_bytes(data)
    try:
        expected = dict(deserialize(data))
        reference_accepts = True
    except safetensors.SafetensorError:
        expected, reference_accepts = None, False
    actual = ocaml(path)
    if actual['ok'] != reference_accepts:
        if policy_difference(data, reference_accepts, actual):
            return None
        return 'acceptance-disagreement', {'reference_accepts': reference_accepts, 'ocaml': actual}
    if not reference_accepts:
        return None
    decoded = unpack(data)
    header, _ = decoded
    got = {tensor['name']: tensor for tensor in actual['tensors']}
    if len(got) != len(actual['tensors']) or got.keys() != expected.keys():
        return 'tensor-names', actual
    if actual['metadata'] != (header.get('__metadata__') or {}):
        return 'metadata', actual
    for name, ref in expected.items():
        tensor = got[name]
        for key in ('dtype', 'shape'):
            if tensor[key] != ref[key]:
                return key + '-mismatch', name
        if bytes.fromhex(tensor['data']) != bytes(ref['data']):
            return 'tensor-bytes', name
        if tensor['data_offsets'] != header[name]['data_offsets']:
            return 'tensor-offsets', name
    return None


def differential(recorder):
    seed = int(os.environ.get('SAFETENSORS_SEED', '1337'))
    count = int(os.environ.get('SAFETENSORS_FUZZ_CASES', '100'))
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'mutation.safetensors'
        for case, operation, location, data in mutations(seed, count):
            recorder.check(data, lambda value: observe(value, path), seed=seed,
                           case=case, mutation=operation, location=location)
            total += 1
    print(f'differential: seed={seed} cases={count} inputs={total}, four-reader/oracle parity')
    return {'seed': seed, 'cases': count, 'inputs': total}


def create_recorder(versions=None):
    return Recorder(REPORTS/'failures', versions or assert_reference_versions(),
                    {'address_space_bytes': 512 * 1024 * 1024,
                     'cpu_seconds': 10, 'max_rank': 64,
                     'max_tensors': 100000, 'max_name_bytes': 4096,
                     'max_metadata_entries': 100000, 'max_header_bytes': 100000000})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=['synthetic', 'hub'])
    args = parser.parse_args()
    versions = assert_reference_versions()
    REPORTS.mkdir(parents=True, exist_ok=True)
    recorder = create_recorder(versions)
    report = {'suite': args.suite, 'reference_version': safetensors.__version__,
              'python': platform.python_version(), 'platform': platform.platform(),
              'reader_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
              'fixture_lock_sha256': hashlib.sha256(LOCK.read_bytes()).hexdigest(),
              'reference_requirements_sha256': hashlib.sha256((ROOT/'scripts/reference-requirements.txt').read_bytes()).hexdigest(),
              'files': []}
    if args.suite == 'synthetic':
        report['compatibility'] = probes(recorder)
        report['differential'] = differential(recorder)
        manifest = json.loads((ROOT/'test/fixtures/manifest.json').read_text())
        for name, entry in manifest['files'].items():
            path = ROOT/'test/fixtures'/name
            verify(path, {'id': name, **entry})
            report['files'].append(record_compare(recorder, path))
    else:
        lock = load_lock()
        for entry in lock['files']:
            path = fixture_path(entry)
            verify(path, entry)
            result = record_compare(recorder, path)
            assert result['tensor_count'] == entry['tensor_count']
            report['files'].append(result)
    target = REPORTS/(args.suite+'.json')
    target.write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(f"{args.suite}: {len(report['files'])} files, {sum(f['tensor_count'] for f in report['files'])} tensors, all access paths byte-exact; {target}")


if __name__ == '__main__':
    main()
