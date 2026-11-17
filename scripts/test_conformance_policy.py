#!/usr/bin/env python3
"""Policy exceptions must never mask unrelated reader acceptance bugs."""
import copy
import unittest
from unittest.mock import patch
from conformance import observe, policy_difference
from conformance_fuzz import frame


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.header = {'x': {'dtype': 'U8', 'shape': [9223372036854775807, 3, 0],
                             'data_offsets': [0, 0]}}

    def actual(self, header, payload=b''):
        data = frame(header, payload)
        tensors = []
        for name, tensor in header.items():
            if name == '__metadata__':
                continue
            start, end = tensor['data_offsets']
            tensors.append({'name': name, 'dtype': tensor['dtype'],
                            'shape': tensor['shape'], 'data_offsets': [start, end],
                            'data': payload[start:end].hex()})
        return data, {'ok': True, 'data_start': len(data) - len(payload),
                      'metadata': header.get('__metadata__', {}), 'tensors': tensors}

    def test_zero_overflow_only_is_allowed(self):
        data, actual = self.actual(self.header)
        self.assertEqual(policy_difference(data, False, actual),
                         'zero dimensions checked before intermediate product overflow')

    def test_other_invalid_tensor_is_not_allowed(self):
        self.header['bad'] = {'dtype': 'U8', 'shape': [1], 'data_offsets': [0, 0]}
        data, actual = self.actual(self.header)
        self.assertIsNone(policy_difference(data, False, actual))

    def test_unknown_fields_are_not_allowed(self):
        self.header['x']['extra'] = 'ignored by oracle'
        data, actual = self.actual(self.header)
        self.assertIsNone(policy_difference(data, False, actual))

    def test_other_tensor_bytes_must_match(self):
        self.header['data'] = {'dtype': 'U8', 'shape': [1], 'data_offsets': [0, 1]}
        data, actual = self.actual(self.header, b'a')
        actual['tensors'][1]['data'] = 'ff'
        self.assertIsNone(policy_difference(data, False, actual))

    def test_original_shape_and_metadata_must_match(self):
        data, actual = self.actual(self.header)
        wrong_shape = copy.deepcopy(actual)
        wrong_shape['tensors'][0]['shape'] = [0]
        self.assertIsNone(policy_difference(data, False, wrong_shape))
        actual['metadata'] = {'invented': 'value'}
        self.assertIsNone(policy_difference(data, False, actual))

    def test_rank_and_signed_integer_caps_are_not_allowed(self):
        self.header['x']['shape'] += [0] * 62
        data, actual = self.actual(self.header)
        self.assertIsNone(policy_difference(data, False, actual))
        self.setUp()
        self.header['unsigned'] = {'dtype': 'U8', 'shape': [9223372036854775808, 0],
                                   'data_offsets': [0, 0]}
        data, actual = self.actual(self.header)
        self.assertIsNone(policy_difference(data, False, actual))

    def test_duplicate_members_are_not_allowed(self):
        data, actual = self.actual(self.header)
        header = data[8:]
        duplicate = header[:-1] + b',' + header[1:]
        self.assertIsNone(policy_difference(frame(duplicate), False, actual))

    def test_observed_disagreement_direction_is_preserved(self):
        class Sink:
            def write_bytes(self, _data):
                pass
        valid = frame({})
        with patch('conformance.ocaml', return_value={'ok': False, 'kind': 'invalid_header'}):
            self.assertEqual(observe(valid, Sink())[0],
                             'acceptance-disagreement:reference=True:ocaml=False:rejection=["invalid_header", null]')
        with patch('conformance.ocaml', return_value={'ok': True}):
            self.assertEqual(observe(b'invalid', Sink())[0],
                             'acceptance-disagreement:reference=False:ocaml=True')

    def test_rejection_kind_and_path_are_part_of_predicate(self):
        class Sink:
            def write_bytes(self, _data):
                pass
        signatures = []
        for kind, path in [('invalid_header', '$["a"]'),
                           ('resource_limit', '$["a"]'),
                           ('invalid_header', '$["b"]')]:
            with patch('conformance.ocaml', return_value={'ok': False, 'kind': kind, 'path': path}):
                signatures.append(observe(frame({}), Sink())[0])
        self.assertEqual(len(set(signatures)), 3)


if __name__ == '__main__':
    unittest.main()
