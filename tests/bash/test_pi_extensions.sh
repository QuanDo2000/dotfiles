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
  assert_equals 6 "$(jq '.packages | length' "$settings")"
  assert_equals 6 "$(jq '.dependencies | length' "$package")"
  assert_equals false "$(jq 'has("overrides")' "$package")"
  assert_equals false "$(jq '.dependencies | has("@ff-labs/pi-fff")' "$package")"
  assert_equals 0 "$(jq '[.packages[] | (if type == "string" then . else .source end) | select(contains("@ff-labs/pi-fff"))] | length' "$settings")"
  assert_equals 0 "$(jq --arg id "$release_id" '[.packages[] | (if type == "string" then . else .source end) | select(startswith("./locked-extensions/releases/" + $id + "/node_modules/") | not)] | length' "$settings")"
  assert_equals 0 "$(jq '[.packages[] | (if type == "string" then . else .source end) | select(startswith("npm:"))] | length' "$settings")"
  assert_equals '[]' "$(jq -c --arg id "$release_id" '[.packages[] | select(type == "object" and .source == ("./locked-extensions/releases/" + $id + "/node_modules/@dietrichgebert/ponytail"))][0].skills // null' "$settings")"
}

test_pi_extension_lock_has_integrity_for_every_tarball() {
  [ -f "$extension_dir/package-lock.json" ] || return

  assert_equals 0 "$(jq '[.packages | to_entries[] | select(.key != "" and (.value.link != true)) | select((.value.resolved | type) != "string" or (.value.integrity | startswith("sha512-") | not))] | length' "$extension_dir/package-lock.json")"
  assert_equals 'node_modules/better-sqlite3' "$(jq -r '[.packages | to_entries[] | select(.value.hasInstallScript == true) | .key] | join(" ")' "$extension_dir/package-lock.json")"
  assert_equals "$(jq -r .betterSqlite3.version "$REPO_DIR/packages/pi-extensions-release.json")" "$(jq -r '.packages["node_modules/better-sqlite3"].version' "$extension_dir/package-lock.json")"
}

test_pi_extensions_nix_package_disables_scripts_and_pins_native_binary() {
  local package home flake check
  package="$(<"$REPO_DIR/packages/pi-extensions.nix")"
  home="$(<"$REPO_DIR/config/home.nix")"
  flake="$(<"$REPO_DIR/flake.nix")"
  check="$(<"$REPO_DIR/scripts/check.sh")"

  assert_contains "$package" 'pi-extensions-release.json'
  assert_contains "$package" 'npmDepsHash = "sha256-'
  assert_contains "$package" '"--ignore-scripts"'
  assert_contains "$package" 'better-sqlite3'
  assert_contains "$package" 'better_sqlite3.node'
  assert_contains "$home" 'locked-extensions/releases/${piExtensionsReleaseId}'
  assert_contains "$flake" 'packages.x86_64-linux.pi-extensions'
  assert_contains "$flake" 'packages.aarch64-darwin.pi-extensions'
  assert_contains "$check" '"$flake#pi-extensions"'
}

test_pi_mcp_uses_native_fff_with_persistent_frecency() {
  local config agents updater
  config="$REPO_DIR/config/shared/ai/pi/mcp.json"
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  updater="$(<"$REPO_DIR/scripts/update_pins.py")"

  assert_exit_code 0 jq -e '
    .mcpServers.fff.command == "fff-mcp-agent" and
    .mcpServers.fff.transport == "stdio" and
    .mcpServers.fff.lifecycle == "eager"
  ' "$config"
  assert_contains "$agents" 'mcp_fff_find_files'
  assert_contains "$agents" 'mcp_fff_grep'
  assert_contains "$agents" 'mcp_fff_multi_grep'
  assert_not_contains "$updater" '@ff-labs/pi-fff'
  assert_not_contains "$updater" '@ff-labs/fff-bun'
  assert_not_contains "$updater" '@ff-labs/fff-node'
}

test_pi_extension_update_reconciles_local_packages_only() {
  local settings packages
  settings="$(<"$REPO_DIR/config/shared/ai/pi/settings.json")"
  packages="$(<"$REPO_DIR/scripts/packages.sh")"

  assert_not_contains "$settings" '"npm:'
  assert_contains "$packages" 'pi update --extensions'
}
