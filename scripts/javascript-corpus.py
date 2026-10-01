#!/usr/bin/env python3
"""Prepare byte-exact native/oracle expectations before isolated JS runs."""
import json
from pathlib import Path
from conformance import compare, ocaml, probes, probe_cases, raw, ROOT
from fetch_fixtures import load_lock, fixture_path, verify

def normalized(value):
    if not value['ok']:
        return {key: value[key] for key in ['ok', 'kind', 'path', 'byte_offset']}
    value['data_start'] = str(value['data_start'])
    for tensor in value['tensors']:
        tensor['shape'] = list(map(str, tensor['shape']))
        tensor['data_offsets'] = list(map(str, tensor['data_offsets']))
    return value

probes()
cases = []
for path in sorted((ROOT/'test/fixtures').glob('*.safetensors')):
    compare(path)
    cases.append({'name': path.name, 'hex': path.read_bytes().hex(),
                  'expected': normalized(ocaml(path))})
for entry in load_lock()['files']:
    path = fixture_path(entry)
    verify(path, entry)
    compare(path)
    cases.append({'name': entry['id'], 'hex': path.read_bytes().hex(),
                  'expected': normalized(ocaml(path))})
temporary = ROOT/'.cache/javascript/probe.safetensors'
for name, data, _, _, _ in probe_cases():
    temporary.write_bytes(data)
    cases.append({'name': name, 'hex': data.hex(), 'expected': normalized(ocaml(temporary))})
for n in [2**31-1, 2**31, 2**32-1, 2**32, 2**53-1, 2**53, 2**53+1, 2**63-1]:
    temporary.write_bytes(raw('{"é☃":{"dtype":"U8","shape":[%d,0],"data_offsets":[0,0]}}' % n))
    cases.append({'name': 'integer-'+str(n), 'hex': temporary.read_bytes().hex(),
                  'expected': normalized(ocaml(temporary))})
temporary.unlink()
target = ROOT/'.cache/javascript/corpus.json'
target.write_text(json.dumps(cases, ensure_ascii=False)+'\n')
print(f'Prepared {len(cases)} cases with native/oracle verification: {target}')
