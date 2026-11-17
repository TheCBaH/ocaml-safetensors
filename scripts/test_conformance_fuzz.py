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

    def test_dotted_fixture_names_keep_distinct_digest_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            recorder = Recorder(directory, {}, {})
            for data in (b'first!', b'second!'):
                with self.assertRaises(AssertionError):
                    recorder.check(data, lambda value: ('trigger', None) if b'!' in value else None,
                                   case='layout.safetensors', mutation='fixture')
            replays = list(Path(directory).glob('*.json'))
            self.assertEqual(len(replays), 2)
            originals = [Path(json.loads(path.read_text())['original']).read_bytes()
                         for path in replays]
            self.assertCountEqual(originals, [b'first!', b'second!'])

    def test_reduction_cannot_reverse_acceptance_disagreement(self):
        with tempfile.TemporaryDirectory() as directory:
            recorder = Recorder(directory, {}, {})
            def observe(data):
                if b'original' in data:
                    return 'acceptance-disagreement:reference=False:ocaml=True', None
                if data:
                    return 'acceptance-disagreement:reference=True:ocaml=False', None
                return None
            with self.assertRaises(AssertionError):
                recorder.check(b'original suffix', observe)
            replay = json.loads(next(Path(directory).glob('*.json')).read_text())
            self.assertIn(b'original', Path(replay['minimized']).read_bytes())
            self.assertEqual(replay['failure'][0], replay['minimized_failure'][0])

    def test_expired_reduction_budget_keeps_original(self):
        def should_not_run(_data):
            self.fail('predicate ran after its reduction deadline')
        reduced, attempts = reduce_failure(b'original', should_not_run, time_budget=0)
        self.assertEqual(reduced, b'original')
        self.assertEqual(attempts, 0)

    def test_seed_replays_identical_mutations(self):
        self.assertEqual(list(mutations(1337, 5)), list(mutations(1337, 5)))
        self.assertTrue(any(op == 'prefix-preserving-byte' for _, op, _, _ in mutations(1337, 1)))


if __name__ == '__main__':
    unittest.main()
