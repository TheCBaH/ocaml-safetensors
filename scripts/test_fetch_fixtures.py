import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import fetch_fixtures as f


class Response(io.BytesIO):
    headers = {}
    def geturl(self):
        return 'https://example.test/file'


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cache = Path(self.tmp.name)
        patcher = patch.object(f, 'CACHE', self.cache)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.entry = dict(id='test', size_bytes=3, sha256=hashlib.sha256(b'abc').hexdigest(), url='https://example.test/file')

    def test_valid_cache_is_rehashed_without_network(self):
        f.fixture_path(self.entry).write_bytes(b'abc')
        with patch.object(f.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            self.assertEqual(f.fetch(self.entry), 'cached')

    def test_corrupt_cache_fails(self):
        f.fixture_path(self.entry).write_bytes(b'bad')
        with patch.object(f.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                f.fetch(self.entry)

    def test_check_only_does_not_download(self):
        with patch.object(f.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            with self.assertRaisesRegex(ValueError, 'not cached'):
                f.fetch(self.entry, check_only=True)

    def test_download_and_atomic_cleanup(self):
        with patch.object(f.urllib.request, 'urlopen', return_value=Response(b'abc')):
            self.assertEqual(f.fetch(self.entry), 'downloaded')
        self.assertEqual(f.fixture_path(self.entry).read_bytes(), b'abc')
        self.assertEqual(len(list(self.cache.iterdir())), 1)

    def test_oversize_short_and_wrong_hash_fail_closed(self):
        for data in [b'abcd', b'ab', b'bad']:
            with self.subTest(data=data), patch.object(f.time, 'sleep'), patch.object(f.urllib.request, 'urlopen', side_effect=lambda *a, **k: Response(data)):
                with self.assertRaises(ValueError):
                    f.fetch(self.entry)
                self.assertEqual(list(self.cache.iterdir()), [])

    def test_total_budget_checked_before_fetch(self):
        lock = json.loads(f.LOCK.read_text())
        lock['limits']['max_suite_bytes'] = 1
        path = self.cache/'lock.json'
        path.write_text(json.dumps(lock))
        with patch.object(f, 'LOCK', path), self.assertRaisesRegex(ValueError, 'total limit'):
            f.load_lock()


if __name__ == '__main__':
    unittest.main()
