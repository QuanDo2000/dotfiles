#!/usr/bin/env bash
# Execute the patched detector with Pi supplied as a virtual module.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() { init_test_env; }
teardown() { cleanup_test_env; }

test_pi_web_activation_patch_uses_host_version_and_preserves_guards() {
  local target="$TEST_TMPDIR/activation.mjs" status=0 before
  cp "$REPO_DIR/tests/fixtures/pi-web-access-activation.mjs" "$target"
  node "$REPO_DIR/scripts/patch_pi_web_activation.cjs" "$target" 2>>"$ERROR_FILE" || status=$?
  assert_equals 0 "$status"
  [[ "$status" == 0 ]] || return
  node --input-type=module - "$target" <<'JS' || status=$?
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(process.argv[2], 'utf8');
const api = { getAllTools() {}, getActiveTools() {}, setActiveTools() {} };
for (const [version, expected] of [['0.86.0', false], ['0.86.1', true], ['0.87.1', true]]) {
  const host = 'data:text/javascript,' + encodeURIComponent(`export const VERSION = '${version}'; export function buildSessionContext() {}`);
  const module = await import('data:text/javascript,' + encodeURIComponent(source.replaceAll('@earendil-works/pi-coding-agent', host)));
  assert.equal(module.supportsDynamicTools(api), expected);
  assert.equal(module.supportsDynamicTools({ ...api, setActiveTools: undefined }), false);
}
JS
  assert_equals 0 "$status"
  before="$(sha256sum "$target")"
  node "$REPO_DIR/scripts/patch_pi_web_activation.cjs" "$target" 2>>"$ERROR_FILE" || status=$?
  node "$REPO_DIR/scripts/patch_pi_web_activation.cjs" "$target" --check 2>>"$ERROR_FILE" || status=$?
  assert_equals 0 "$status"
  assert_equals "$before" "$(sha256sum "$target")"
}

test_pi_web_activation_patch_rejects_drift_without_writing() {
  local target="$TEST_TMPDIR/activation.mjs" status=0 before
  printf 'upstream changed\n' > "$target"
  before="$(sha256sum "$target")"
  node "$REPO_DIR/scripts/patch_pi_web_activation.cjs" "$target" 2>"$TEST_TMPDIR/error" || status=$?
  assert_equals 1 "$status"
  assert_contains "$(<"$TEST_TMPDIR/error")" 'Pi web activation patch source drift'
  assert_equals "$before" "$(sha256sum "$target")"
}
