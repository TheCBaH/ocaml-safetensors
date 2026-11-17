#!/usr/bin/env python3
"""Check replay preservation and reduction of both valid and invalid inputs."""
import json
from pathlib import Path
import tempfile
import unittest
from conformance_fuzz import Recorder, frame, mutations, reduce_failure, unpack


class ReductionTests(unittest.TestCase):
    def test_interior_tensor_subset_and_metadata(self):
        source = frame({'a': {}, 'trigger': {'shape': [2, 3, 4]}, 'z': {},
                        '__metadata__': {'irrelevant': 'value'}}, b'payload')
        def fails(data):
            decoded = unpack(data)
            return bool(decoded and isinstance(decoded[0], dict)
                        and 'trigger' in decoded[0])
        reduced, _ = reduce_failure(source, fails)
        self.assertTrue(fails(reduced))
        self.assertLess(len(reduced), len(source))
        self.assertNotIn('a', unpack(reduced)[0])
        self.assertNotIn('__metadata__', unpack(reduced)[0])

    def test_invalid_inputs_keep_trigger(self):
        source = b'invalid JSON before ! after'
        reduced, _ = reduce_failure(source, lambda data: b'!' in data)
        self.assertEqual(reduced, b'!')

    def test_dimension_and_irrelevant_payload_reduction(self):
        source = frame({'trigger': {'shape': [2, 3, 4]}}, b'x' * 100)
        def fails(data):
            decoded = unpack(data)
            return bool(decoded and isinstance(decoded[0], dict)
                        and decoded[0].get('trigger', {}).get('shape') == [3])
        # A bug that depends on a particular dimension still survives removal
        # of neighboring dimensions; reducer need not require valid storage.
        def same_bug(data):
            decoded = unpack(data)
            return bool(decoded and isinstance(decoded[0], dict)
                        and 3 in decoded[0].get('trigger', {}).get('shape', []))
        reduced, _ = reduce_failure(source, same_bug)
        self.assertTrue(fails(reduced))
        self.assertEqual(unpack(reduced)[1], b'')

    def test_exceptions_preserve_original_and_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            recorder = Recorder(directory, {'reader': 'test'}, {'rank': 64})
            def crashes(data):
                if b'!' in data:
                    raise RuntimeError('trigger')
                return None
            with self.assertRaisesRegex(AssertionError, 'replay='):
                recorder.check(b'prefix!suffix', crashes, seed=7, case=4,
                               mutation='byte', location=6)
            replay = json.loads(next(Path(directory).glob('*.json')).read_text())
            self.assertEqual(replay['seed'], 7)
            self.assertEqual(Path(replay['original']).read_bytes(), b'prefix!suffix')
            self.assertEqual(Path(replay['minimized']).read_bytes(), b'!')
            self.assertEqual(replay['versions'], {'reader': 'test'})

    def test_seed_replays_identical_mutations(self):
        self.assertEqual(list(mutations(1337, 5)), list(mutations(1337, 5)))
        self.assertTrue(any(op == 'prefix-preserving-byte' for _, op, _, _ in mutations(1337, 1)))


if __name__ == '__main__':
    unittest.main()
