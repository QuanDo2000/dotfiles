#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_pi_auth_preserves_ready_credentials_and_reports_only_missing_logins() {
  assert_exit_code 0 python3 - "$REPO_DIR/scripts/pi_auth.py" <<'PY'
import importlib.util
import subprocess
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pi_auth", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def check(cmd, **kwargs):
    assert cmd[-2:] == ["--json", "--no-refresh"]
    assert kwargs["env"]["PI_OFFLINE"] == "1"
    assert kwargs["timeout"] == 30
    provider = cmd[4]
    if provider == "openai-codex":
        return subprocess.CompletedProcess(cmd, 0, '{"status":"ready","authType":"oauth"}')
    return subprocess.CompletedProcess(cmd, 1, '{"status":"not_ready"}')

with patch.object(module.subprocess, "run", side_effect=check) as run:
    assert module.missing_providers("pi", {"PI_OFFLINE": "1"}) == ["openrouter"]
    assert run.call_count == 2

for raw in ['SECRET_FROM_NATIVE_AUTH', '[]']:
    with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, raw)):
        try:
            module.missing_providers("pi", {})
        except RuntimeError as error:
            assert "SECRET_FROM_NATIVE_AUTH" not in str(error)
        else:
            raise AssertionError("Invalid auth output must fail closed")
PY
}

test_pi_auth_dry_run_does_not_launch_login() {
  local output status=0
  output=$(bash "$DOTFILE_CMD" -d pi-auth 2>&1) || status=$?
  assert_equals 0 "$status"
  assert_contains "$output" 'Checking Pi Codex subscription and OpenRouter authentication'
  assert_not_contains "$output" 'Pi setup failed'
}

test_pi_auth_resolves_managed_mac_and_windows_packages() {
  assert_exit_code 0 python3 - "$REPO_DIR/scripts/pi_auth.py" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import tempfile
from unittest.mock import patch
import sys
import shutil
spec = importlib.util.spec_from_file_location('pi_auth', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory, patch.dict(os.environ, {'PI_PACKAGE_DIR': ''}):
    prefix = Path(directory)
    root = prefix / 'lib/node_modules/@earendil-works/pi-coding-agent'
    (root / 'dist/core').mkdir(parents=True)
    (root / 'dist/core/auth-storage.js').touch()
    (root / 'package.json').write_text(json.dumps({'name': '@earendil-works/pi-coding-agent'}))
    (prefix / 'bin').mkdir()
    pi = prefix / 'bin/pi'
    pi.touch()
    assert module.package_directory(pi) == root.resolve()
    release = prefix / 'releases/1.4.0'
    shutil.copytree(root, release)
    launcher = prefix / 'bin/pi.cmd'
    launcher.write_text('@echo off\nnode "' + str(release) + '/dist/bundle/cli.js" %*\n')
    assert module.package_directory(launcher) == release.resolve()
PY
}

test_pi_auth_native_credential_store() {
  assert_exit_code 0 python3 - "$REPO_DIR/scripts/pi_auth.py" "$REPO_DIR/tests/fixtures/pi-auth-store.mjs" <<'PY'
import importlib.util
import shutil
import subprocess
import sys
spec = importlib.util.spec_from_file_location("pi_auth", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
subprocess.run(["node", sys.argv[2], str(module.package_directory(shutil.which("pi")))], check=True, timeout=30)
PY
}

test_pi_auth_missing_login_uses_terminal_helper_not_agent_ui() {
  assert_exit_code 0 python3 - "$REPO_DIR/scripts/pi_auth.py" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pi_auth", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
    root = Path(directory)
    (root / 'package.json').write_text(json.dumps({'name': '@earendil-works/pi-coding-agent'}))
    (root / 'dist/core').mkdir(parents=True)
    (root / 'dist/core/auth-storage.js').touch()
    def launch(command, **kwargs):
        assert Path(command[0]).name == 'node', 'Login must not launch the Pi agent UI'
        assert Path(command[1]).name == 'pi_auth_login.mjs'
        assert command[2:] == [str(root.resolve()), 'openrouter']
        assert 'DOTFILE_PI_AUTH_MISSING' not in kwargs['env']
        return subprocess.CompletedProcess(command, 0)
    with patch.dict(os.environ, {'PI_PACKAGE_DIR': str(root)}), \
         patch.object(sys, 'argv', ['pi_auth.py']), \
         patch.object(sys.stdin, 'isatty', return_value=True), \
         patch.object(sys.stdout, 'isatty', return_value=True), \
         patch.object(module.shutil, 'which', side_effect=lambda name: '/tools/' + name), \
         patch.object(module, 'missing_providers', side_effect=[['openrouter'], []]), \
         patch.object(module.subprocess, 'run', side_effect=launch):
        assert module.main() == 0
PY
}
