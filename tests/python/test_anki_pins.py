import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import update_pins


class AnkiPinsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.pins = self.repo / 'config/windows/anki-addons.json'
        self.pins.parent.mkdir(parents=True)
        self.original = [{'id': '2055492159', 'name': 'AnkiConnect',
                          'url': 'https://ankiweb.net/shared/download/2055492159?v=2.1&p=2509004',
                          'sha256': '0' * 64, 'config': {'webBindAddress': '127.0.0.1'}}]
        self.pins.write_text(json.dumps(self.original), encoding='utf-8')

    def download(self, url, destination):
        with zipfile.ZipFile(destination, 'w') as archive:
            archive.writestr('__init__.py', '# reviewed fixture\n')
            archive.writestr('user_files/data.txt', 'default mutable data')

    def test_refresh_preserves_settings_and_records_code_hashes(self):
        with patch.object(update_pins, 'download_twice', self.download):
            status = self.run_updater()
        self.assertEqual(status, 0)
        pin = json.loads(self.pins.read_text())[0]
        self.assertEqual(pin['config'], self.original[0]['config'])
        self.assertNotEqual(pin['sha256'], '0' * 64)
        self.assertEqual(pin['files'], {'__init__.py': hashlib.sha256(b'# reviewed fixture\n').hexdigest()})

    def run_updater(self):
        errors = io.StringIO()
        with patch.object(sys, 'argv', ['update_pins.py', 'anki-addons', str(self.repo)]), contextlib.redirect_stderr(errors):
            status = update_pins.main()
        self.last_error = errors.getvalue()
        return status

    def test_unsafe_archives_leave_pins_unchanged(self):
        for name in ('../escape', 'C:/escape', 'dir\\escape', 'dir/../../escape'):
            with self.subTest(name=name):
                def unsafe(url, destination):
                    self.download(url, destination)
                    with zipfile.ZipFile(destination, 'a') as archive:
                        entry = zipfile.ZipInfo('placeholder')
                        entry.filename = name
                        archive.writestr(entry, 'bad')
                with patch.object(update_pins, 'download_twice', unsafe):
                    self.assertNotEqual(self.run_updater(), 0)
                    self.assertIn('unsafe Anki add-on archive', self.last_error)
                self.assertEqual(json.loads(self.pins.read_text()), self.original)

    def test_missing_entrypoint_leaves_pins_unchanged(self):
        def invalid(url, destination):
            with zipfile.ZipFile(destination, 'w') as archive:
                archive.writestr('not-an-addon.txt', 'no code')
        with patch.object(update_pins, 'download_twice', invalid):
            self.assertNotEqual(self.run_updater(), 0)
            self.assertIn('missing __init__.py', self.last_error)
        self.assertEqual(json.loads(self.pins.read_text()), self.original)


if __name__ == '__main__':
    unittest.main()
