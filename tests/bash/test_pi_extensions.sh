#!/usr/bin/env bash
# Integrity-locked Pi extension package tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

extension_dir="$REPO_DIR/config/shared/ai/pi/extensions"
release_file="$REPO_DIR/packages/pi-extensions-release.json"

_lock_sha256() {
  python3 - "$extension_dir/package-lock.json" <<'PY'
import hashlib
import sys

print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
}

test_pi_extension_lock_keeps_lf_bytes_on_windows() {
  assert_file_exists "$REPO_DIR/.gitattributes"
  [ -f "$REPO_DIR/.gitattributes" ] || return
  assert_contains "$(<"$REPO_DIR/.gitattributes")" 'config/shared/ai/pi/extensions/package-lock.json text eol=lf'
}

test_pi_extension_settings_use_locked_local_release() {
  assert_file_exists "$release_file"
  assert_file_exists "$extension_dir/package.json"
  assert_file_exists "$extension_dir/package-lock.json"
  [ -f "$release_file" ] && [ -f "$extension_dir/package-lock.json" ] || return

  local release_id settings package
  release_id="$(jq -r .releaseId "$release_file")"
  settings="$REPO_DIR/config/shared/ai/pi/settings.json"
  package="$extension_dir/package.json"

  assert_equals "$release_id" "$(_lock_sha256)"
  assert_equals '["@tobilu/qmd","pi-memory","pi-web-access"]' "$(jq -c '.dependencies | keys | sort' "$package")"
  assert_equals '["pi-memory","pi-web-access"]' "$(jq -c '[.packages[] | split("/")[-1]] | sort' "$settings")"
  assert_equals false "$(jq 'has("overrides")' "$package")"
  assert_equals 0 "$(jq --arg id "$release_id" '[.packages[] | (if type == "string" then . else .source end) | select(startswith("./locked-extensions/releases/" + $id + "/node_modules/") | not)] | length' "$settings")"
  assert_equals 0 "$(jq '[.packages[] | (if type == "string" then . else .source end) | select(startswith("npm:"))] | length' "$settings")"
}


test_pi_extension_lock_has_integrity_for_every_tarball() {
  [ -f "$extension_dir/package-lock.json" ] || return

  assert_equals 0 "$(jq '[.packages | to_entries[] | select(.key != "" and (.value.link != true)) | select((.value.resolved | type) != "string" or (.value.integrity | startswith("sha512-") | not))] | length' "$extension_dir/package-lock.json")"
}

test_pi_extensions_evaluated_packages_disable_scripts_and_require_install_checks() {
  local system safe
  for system in x86_64-linux aarch64-darwin; do
    safe="$(command nix eval --json "path:$REPO_DIR#packages.$system.pi-extensions" --apply '
      package: builtins.elem "--ignore-scripts" package.npmFlags
        && package.doInstallCheck && package.npmDeps.outputHash != ""
    ')"
    assert_equals true "$safe"
  done
}


test_pi_extension_update_reconciles_local_packages_only() {
  local pi_calls="$TEST_TMPDIR/pi-calls"
  : > "$pi_calls"
  pi() { printf '%s\n' "$@" >> "$pi_calls"; }
  assert_exit_code 0 _update_pi_extensions
  assert_equals $'update\n--extensions' "$(<"$pi_calls")"

  : > "$pi_calls"
  DRY=true
  assert_exit_code 0 _update_pi_extensions
  assert_equals '' "$(<"$pi_calls")"
}

test_pi_extension_update_failure_stops_the_caller() {
  pi() { return 42; }
  local output status=0
  output="$(_update_pi_extensions; printf 'unexpected continuation')" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'Failed to update Pi extensions'
}
