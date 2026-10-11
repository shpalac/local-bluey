"""Fabricated offline PNG inventory fixtures, no screenshot or network access."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib
import golden_failure_manifest as manifest


def chunk(kind, data):
    return (struct.pack('>I', len(data)) + kind + data +
            struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))


def png():
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\xff')) + chunk(b'IEND', b''))


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.baseline = self.root / 'test/screenshots/goldens'
        self.failures = self.baseline / 'failures'
        self.failures.mkdir(parents=True)
        (self.baseline / 'fixture.png').write_bytes(png())
        self.path = self.failures / 'fixture_testImage.png'

    def test_no_evidence_is_not_pass(self):
        self.assertEqual(manifest.inventory(self.root)['status'], 'no-evidence')

    def test_valid_is_deterministic_but_requires_review(self):
        self.path.write_bytes(png())
        first = manifest.inventory(self.root)
        self.assertEqual(first, manifest.inventory(self.root))
        self.assertEqual(first['status'], 'review-required')
        self.assertEqual(first['privacy'], 'not-established')
        self.assertEqual(first['comparison'], 'not-established')
        self.assertEqual(first['files'][0]['width'], 1)
        self.assertNotIn(str(self.root), json.dumps(first))
        self.assertEqual(self.path.read_bytes(), png())

    def test_unknown_name_and_directory_rejected(self):
        bad = self.failures / 'private.png'
        bad.write_bytes(png())
        with self.assertRaises(ValueError):
            manifest.inventory(self.root)
        bad.unlink()
        self.path.mkdir()
        with self.assertRaises(ValueError):
            manifest.inventory(self.root)

    def test_symlink_file_and_directory_rejected(self):
        self.path.symlink_to(self.baseline / 'fixture.png')
        with self.assertRaises(ValueError):
            manifest.inventory(self.root)
        self.path.unlink()
        self.failures.rmdir()
        self.failures.symlink_to(self.baseline)
        with self.assertRaises(ValueError):
            manifest.inventory(self.root)

    def test_corrupt_truncated_trailing_and_missing_end_rejected(self):
        for data in [b'not png', png()[:20], png() + b'extra', png()[:-12],
                     png()[:-1] + b'x']:
            self.path.write_bytes(data)
            with self.assertRaises(ValueError):
                manifest.inventory(self.root)

    def test_file_total_count_and_pixel_bounds(self):
        self.path.write_bytes(png())
        for setting in ['MAX_BYTES', 'MAX_TOTAL', 'MAX_FILES', 'MAX_PIXELS']:
            with patch.object(manifest, setting, 0):
                with self.assertRaises(ValueError):
                    manifest.inventory(self.root)

    def test_cli_failure_does_not_echo_private_path_or_bytes(self):
        self.path.write_bytes(b'fabricated-private-content')
        run = subprocess.run([sys.executable, manifest.__file__, str(self.root)],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertEqual(run.stdout, '')
        self.assertNotIn(str(self.root), run.stderr)
        self.assertNotIn('fabricated-private-content', run.stderr)

    def test_missing_baselines_rejected(self):
        (self.baseline / 'fixture.png').unlink()
        with self.assertRaises(ValueError):
            manifest.inventory(self.root)


if __name__ == '__main__':
    unittest.main()
