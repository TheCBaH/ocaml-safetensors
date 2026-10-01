#!/usr/bin/env python3
"""Acquire only the bounded, immutable files in the reviewed fixture lock."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'ocaml-safetensors-fixtures.json'
CACHE = ROOT / '.cache' / 'fixtures'


def load_lock():
    lock = json.loads(LOCK.read_text())
    entries = lock['files']
    if len({e['id'] for e in entries}) != len(entries):
        raise ValueError('duplicate fixture id')
    total = 0
    for e in entries:
        if not e['id'].replace('-', '').isalnum():
            raise ValueError('invalid fixture id')
        if len(e['revision']) != 40 or any(c not in '0123456789abcdef' for c in e['revision']):
            raise ValueError('fixture revision must be a full commit')
        expected = f"https://huggingface.co/{e['repo_id']}/resolve/{e['revision']}/{e['filename']}"
        if e['url'] != expected or len(e['sha256']) != 64:
            raise ValueError('invalid pinned source')
        if not 0 < e['size_bytes'] <= lock['limits']['max_file_bytes']:
            raise ValueError('fixture exceeds per-file limit')
        total += e['size_bytes']
    if total != lock['total_file_bytes'] or total > lock['limits']['max_suite_bytes']:
        raise ValueError('fixture suite exceeds total limit')
    return lock


def fixture_path(e):
    return CACHE / (e['id'] + '.safetensors')


def verify(path, entry):
    if not path.is_file() or path.stat().st_size != entry['size_bytes']:
        raise ValueError(f"{entry['id']}: missing file or size mismatch")
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            digest.update(block)
    if digest.hexdigest() != entry['sha256']:
        raise ValueError(f"{entry['id']}: SHA-256 mismatch")


def fetch(e, *, check_only=False):
    dst = fixture_path(e)
    if dst.exists():
        verify(dst, e)  # Corrupt cache entries fail; never silently reuse them.
        return 'cached'
    if check_only:
        raise ValueError(f"{e['id']}: not cached; run make fixtures.fetch")
    CACHE.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        tmp = None
        try:
            start = time.monotonic()
            request = urllib.request.Request(e['url'], headers={'User-Agent': 'ocaml-safetensors-conformance/1'})
            with urllib.request.urlopen(request, timeout=30) as response:
                if not response.geturl().startswith('https://'):
                    raise ValueError('non-HTTPS download redirect')
                if response.headers.get('Content-Length') and int(response.headers['Content-Length']) != e['size_bytes']:
                    raise ValueError('download content length mismatch')
                with tempfile.NamedTemporaryFile(dir=CACHE, prefix='.download-', delete=False) as out:
                    tmp = Path(out.name)
                    count = 0
                    while True:
                        block = response.read(min(65536, e['size_bytes'] - count + 1))
                        if not block:
                            break
                        count += len(block)
                        if count > e['size_bytes'] or time.monotonic() - start > 90:
                            raise ValueError('download byte/time budget exceeded')
                        out.write(block)
            verify(tmp, e)
            os.replace(tmp, dst)
            return 'downloaded'
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)
        finally:
            if tmp is not None and tmp.exists():
                tmp.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    lock = load_lock()
    for e in lock['files']:
        print(e['id'], fetch(e, check_only=args.check_only), e['size_bytes'], flush=True)
    print(f"verified {len(lock['files'])} files, {lock['total_file_bytes']} bytes")


if __name__ == '__main__':
    main()
