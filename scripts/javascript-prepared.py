#!/usr/bin/env python3
"""Check artifacts for offline consumers without fetching or regenerating them."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAMP = ROOT / '.cache/javascript/prepared.json'


def artifacts():
    return [ROOT / name for name in [
        '.cache/javascript/corpus.json',
        '.cache/javascript/jsoo/_build/default/main.bc.js',
        '.cache/javascript/melange/_build/default/out/main.js',
        '.cache/javascript/native/lib/safetensors/META',
        '.cache/javascript/bigarray/installed/lib/melange-bigarray/META',
        'javascript/node_modules/playwright/package.json',
        'javascript/node_modules/esbuild/package.json',
    ]]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs():
    paths = []
    for directory in ['src', 'javascript', 'test/fixtures']:
        paths += [p for p in (ROOT / directory).rglob('*') if p.is_file()
                  and not {'node_modules', '__pycache__'} & set(p.parts)]
    paths += [ROOT / 'scripts' / name for name in [
        'javascript-build.sh', 'javascript-install.sh', 'javascript-corpus.py',
        'javascript-prepared.py', 'melange-bigarray.sh', 'package-version.py',
        'reference_versions.py', 'reference-requirements.txt', 'conformance.py',
        'conformance_fuzz.py', 'fetch_fixtures.py', 'offline.sh',
    ]]
    paths += [ROOT / 'Makefile', ROOT / 'dune-project', ROOT / 'test/core_cases.ml']
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def provider():
    path = 'vendor/melange-bigarray'
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    indexed = git('ls-files', '--stage', '--', path).split()
    if len(indexed) != 4 or indexed[0] != '160000' or indexed[2] != '0':
        raise ValueError('melange-bigarray requires one resolved gitlink')
    return {'path': path, 'gitlink': indexed[1],
            'checkout': git('-C', path, 'rev-parse', 'HEAD'),
            'dirty': bool(git('-C', path, 'status', '--porcelain', '--untracked-files=all'))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', action='store_true')
    args = parser.parse_args()
    missing = [str(p.relative_to(ROOT)) for p in artifacts() if not p.is_file()]
    if missing:
        parser.error('run make js.prepare first; missing: ' + ', '.join(missing))
    dependency = provider()
    if dependency['gitlink'] != dependency['checkout'] or dependency['dirty']:
        parser.error('melange-bigarray checkout must be clean and match its gitlink')
    current = {'provider': dependency, 'inputs': inputs(), 'artifacts': {
        str(p.relative_to(ROOT)): digest(p) for p in artifacts()}}
    if args.record:
        STAMP.write_text(json.dumps(current, indent=2, sort_keys=True) + '\n')
    elif not STAMP.is_file() or json.loads(STAMP.read_text()) != current:
        parser.error('prepared artifacts are stale; run make js.prepare first')


if __name__ == '__main__':
    main()
