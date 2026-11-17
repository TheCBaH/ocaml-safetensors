"""Replayable differential mutations and predicate-preserving reduction."""
import copy
import hashlib
import json
import random
import struct
import time
from pathlib import Path


def frame(header, payload=b''):
    if not isinstance(header, bytes):
        header = json.dumps(header, ensure_ascii=False, separators=(',', ':')).encode()
    return struct.pack('<Q', len(header)) + header + payload


def unpack(data):
    if len(data) < 8:
        return None
    length = struct.unpack('<Q', data[:8])[0]
    if length > len(data) - 8:
        return None
    try:
        return json.loads(data[8:8 + length]), data[8 + length:]
    except (ValueError, UnicodeError):
        return None


def mutations(seed, count):
    rng = random.Random(seed)
    widths = {'U8': 1, 'F32': 4, 'F8_E4M3': 1, 'C64': 8}
    for case in range(count):
        tensors, payload = {}, b''
        for i in range(rng.randrange(1, 7)):
            dtype = rng.choice(list(widths))
            shape = [rng.randrange(4) for _ in range(rng.randrange(4))]
            length = widths[dtype]
            for dim in shape:
                length *= dim
            start = len(payload)
            payload += rng.randbytes(length)
            tensors[f'tensor.{i}'] = {'dtype': dtype, 'shape': shape,
                                      'data_offsets': [start, len(payload)]}
        tensors['__metadata__'] = {'seed': str(seed), 'case': str(case)}
        data = frame(tensors, payload)
        yield case, 'valid', None, data
        name = rng.choice([n for n in tensors if n != '__metadata__'])
        for operation in ('shape-number', 'offset-number', 'dtype', 'schema-sort',
                          'unknown-field', 'metadata-sort', 'duplicate', 'byte',
                          'arbitrary', 'prefix-preserving-byte'):
            header = copy.deepcopy(tensors)
            location = name
            if operation == 'shape-number':
                value = rng.choice([-1, 9223372036854775808, 0.5, '0', None])
                header[name]['shape'] = [value, 0]
                location += '.shape[0]'
            elif operation == 'offset-number':
                header[name]['data_offsets'][rng.randrange(2)] = rng.choice([-1, 1, 9223372036854775808])
                location += '.data_offsets'
            elif operation == 'dtype':
                header[name]['dtype'] = rng.choice(['UNKNOWN', 'F4', 'F8_E5M2', 'C64'])
                location += '.dtype'
            elif operation == 'schema-sort':
                key = rng.choice(['shape', 'data_offsets', 'dtype'])
                header[name][key] = rng.choice([None, {}, True, 'text', []])
                location += '.' + key
            elif operation == 'unknown-field':
                header[name]['extra'] = {'bounded': [1, 2]}
                location += '.extra'
            elif operation == 'metadata-sort':
                header['__metadata__']['seed'] = rng.choice([None, 1, [], {}])
                location = '__metadata__.seed'
            elif operation == 'duplicate':
                encoded = json.dumps(header, separators=(',', ':')).encode()
                member = json.dumps(name).encode() + b':' + json.dumps(header[name], separators=(',', ':')).encode()
                result = frame(encoded[:-1] + b',' + member + b'}', payload)
                yield case, operation, location, result
                continue
            elif operation == 'arbitrary':
                yield case, operation, 0, rng.randbytes(rng.randrange(256))
                continue
            elif operation in ('byte', 'prefix-preserving-byte'):
                result = bytearray(data)
                start = 8 if operation == 'prefix-preserving-byte' else 0
                position = rng.randrange(start, len(result))
                result[position] = rng.randrange(256)
                yield case, operation, position, bytes(result)
                continue
            yield case, operation, location, frame(header, payload)


def candidates(data):
    decoded = unpack(data)
    if decoded:
        header, payload = decoded
        if isinstance(header, dict):
            keys = list(header)
            # Subsets at every granularity, including interior tensor members.
            for width in sorted({1, max(1, len(keys) // 2)}):
                for start in range(0, len(keys), width):
                    reduced = {k: v for k, v in header.items() if k not in keys[start:start + width]}
                    yield frame(reduced, payload)
            for name, tensor in header.items():
                if name == '__metadata__' and isinstance(tensor, dict):
                    for key in tensor:
                        reduced = copy.deepcopy(header)
                        del reduced[name][key]
                        yield frame(reduced, payload)
                if isinstance(tensor, dict):
                    shape = tensor.get('shape')
                    if isinstance(shape, list):
                        for dimension in range(len(shape)):
                            reduced = copy.deepcopy(header)
                            del reduced[name]['shape'][dimension]
                            yield frame(reduced, payload)
                    for key in tensor:
                        reduced = copy.deepcopy(header)
                        del reduced[name][key]
                        yield frame(reduced, payload)
        for length in sorted({0, len(payload) // 2, max(0, len(payload) - 1)}):
            if length < len(payload):
                yield frame(data[8:len(data) - len(payload)] if payload else data[8:], payload[:length])
    # Invalid JSON and prefix failures also reduce; validity is never required.
    for width in sorted({1, max(1, len(data) // 2)}, reverse=True):
        for start in range(0, len(data), width):
            yield data[:start] + data[start + width:]


def reduce_failure(data, predicate, budget=300, time_budget=30):
    current, attempts = data, 0
    deadline = time.monotonic() + time_budget
    while attempts < budget and time.monotonic() < deadline:
        changed = False
        for candidate in candidates(current):
            if time.monotonic() >= deadline:
                break
            if len(candidate) >= len(current):
                continue
            attempts += 1
            if predicate(candidate):
                current, changed = candidate, True
                break
            if attempts >= budget:
                break
        if not changed:
            break
    return current, attempts


class Recorder:
    def __init__(self, directory, versions, limits):
        self.directory = Path(directory)
        self.versions = versions
        self.limits = limits

    def check(self, data, observe, *, seed=None, case=None, mutation='fixture', location=None):
        def failure(candidate):
            try:
                return observe(candidate)
            except Exception as error:
                stderr = getattr(error, 'stderr', None)
                if isinstance(stderr, bytes):
                    stderr = stderr.decode('utf-8', errors='replace')
                detail = stderr or str(error)
                return 'exception:' + type(error).__name__ + ':' + detail, repr(error)
        result = failure(data)
        if result is None:
            return
        signature = result[0]
        self.directory.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(data).hexdigest()[:16]
        prefix = self.directory / f'{seed}-{case}-{mutation}-{digest}'
        original = Path(str(prefix) + '.safetensors')
        original.write_bytes(data)
        details = {'seed': seed, 'case': case, 'mutation': mutation, 'location': location,
                   'versions': self.versions, 'limits': self.limits, 'failure': result,
                   'original': str(original), 'sha256': hashlib.sha256(data).hexdigest()}
        replay = Path(str(prefix) + '.json')
        replay.write_text(json.dumps(details, indent=2, sort_keys=True) + '\n')
        minimal, attempts = reduce_failure(data, lambda value: (failure(value) or (None,))[0] == signature)
        target = Path(str(prefix) + '.min.safetensors')
        target.write_bytes(minimal)
        details.update(minimized=str(target), reduction_attempts=attempts,
                       minimized_failure=failure(minimal))
        replay.write_text(json.dumps(details, indent=2, sort_keys=True) + '\n')
        raise AssertionError(f'{signature}: replay={replay}, bytes={original}, minimized={target}')
