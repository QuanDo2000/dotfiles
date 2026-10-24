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

test_pi_auth_widget_guides_only_missing_providers() {
  assert_exit_code 0 node - "$REPO_DIR/scripts/pi_auth_ui.js" <<'JS'
const assert = require('node:assert/strict');
const extension = require(process.argv[2]);
for (const missing of ['openai-codex', 'openrouter', 'openai-codex,openrouter']) {
  process.env.DOTFILE_PI_AUTH_MISSING = missing;
  let widget;
  extension({ on(event, callback) {
    assert.equal(event, 'session_start');
    callback({}, { hasUI: true, ui: { setWidget(key, lines) { widget = { key, lines }; } } });
  } });
  assert.equal(widget.key, 'dotfile-provider-login');
  const text = widget.lines.join('\n');
  for (const provider of ['openai-codex', 'openrouter']) {
    assert.equal(text.includes('/login ' + provider), missing.split(',').includes(provider));
  }
  assert.match(text, /\/quit.*verify/);
}
JS
}
