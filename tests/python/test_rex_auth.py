"""Credential persistence checks; no network or real credentials required."""
from email.message import Message
import importlib.util
import netrc
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import urllib.error
import urllib.request

SPEC = importlib.util.spec_from_file_location("rex_auth", Path(__file__).resolve().parents[2] / "scripts/rex_auth.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Cannot load Rex authentication helper")
AUTH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUTH)


class TokenPersistence(unittest.TestCase):
    def test_preserves_entries_and_uses_private_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "netrc"
            original = b"# Preserve comment\nmachine example.com login other password dummy\n"
            path.write_bytes(original)
            path.chmod(0o600)
            AUTH.save_token(path, "test-token")
            self.assertTrue(path.read_bytes().startswith(original))
            self.assertEqual(netrc.netrc(path).authenticators(AUTH.HOST), ("rex", "", "test-token"))
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                AUTH.save_token(path, "replacement")
            self.assertEqual(path.read_bytes(), before)

    def test_rejects_symlink_and_invalid_input_without_data_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target"
            target.write_text("untouched")
            path = Path(directory) / "netrc"
            path.symlink_to(target)
            with self.assertRaises(OSError):
                AUTH.save_token(path, "test-token")
            self.assertEqual(target.read_text(), "untouched")
            path.unlink()
            for invalid in ("", "line\nbreak", 'a"b', "a\\b", "a#b"):
                with self.subTest(token=invalid), self.assertRaises(ValueError):
                    AUTH.save_token(path, invalid)
                self.assertFalse(path.exists())


class RedirectValidation(unittest.TestCase):
    def run_redirect(self, destination):
        def build(handler_type):
            handler = handler_type()
            def open_request(request, timeout):
                self.assertTrue(request.has_header("Authorization"))
                redirected = handler.redirect_request(request, None, 302, "Found", {}, destination)
                if redirected is None:
                    raise urllib.error.HTTPError(request.full_url, 302, "Found", Message(), None)
                self.assertFalse(redirected.has_header("Authorization"))
                self.assertEqual(redirected.get_method(), "HEAD")
                response = mock.MagicMock()
                response.__enter__.return_value.status = 200
                return response
            return mock.Mock(open=open_request)
        with mock.patch.object(AUTH.os, "geteuid", return_value=0), mock.patch.object(AUTH.os, "isatty", return_value=True), mock.patch.object(AUTH.getpass, "getpass", return_value="dummy-token"), mock.patch.object(AUTH.urllib.request, "build_opener", side_effect=build), mock.patch.object(AUTH, "save_token") as save:
            AUTH.main()
            save.assert_called_once_with(Path("/etc/nix/netrc"), "dummy-token")

    def test_refuses_echoed_getpass_fallback(self):
        def failed_hidden_input(prompt):
            AUTH.warnings.warn("Cannot control echo", AUTH.getpass.GetPassWarning)
            self.fail("Echoed input fallback was reached")
        with mock.patch.object(AUTH.os, "geteuid", return_value=0), mock.patch.object(AUTH.os, "isatty", return_value=True), mock.patch.object(AUTH.getpass, "getpass", side_effect=failed_hidden_input), mock.patch.object(AUTH.urllib.request, "build_opener") as opener:
            with self.assertRaises(SystemExit):
                AUTH.main()
            opener.assert_not_called()

    def test_accepts_https_download_redirect_without_forwarding_token(self):
        self.run_redirect("https://downloads.example.org/rex.tar.gz?signature=dummy")

    def test_refuses_insecure_or_credential_bearing_redirect(self):
        for destination in ("http://downloads.example.org/rex", "https://user:pass@downloads.example.org/rex"):
            with self.subTest(destination=destination), self.assertRaises(SystemExit):
                self.run_redirect(destination)


if __name__ == "__main__":
    unittest.main()
