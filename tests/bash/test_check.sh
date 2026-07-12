#!/usr/bin/env bash
# Local verification entrypoint coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_check_script_runs_repo_verification() {
  local check_text flake_text
  check_text="$(<"$REPO_DIR/scripts/check.sh")"
  flake_text="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$check_text" 'bash "$repo_dir/tests/bash/runner.sh" --no-docker'
  assert_contains "$check_text" 'pwsh "$repo_dir/tests/powershell/runner.ps1"'
  assert_contains "$check_text" 'nix flake check --no-build --all-systems'
  assert_contains "$check_text" 'nix build "$repo_dir#codex" "$repo_dir#obsidian-headless" "$repo_dir#pi-agent" --no-link'
  assert_contains "$check_text" 'nix develop "$repo_dir" -c shellcheck'
  assert_contains "$flake_text" "pi-agent = final.callPackage ./packages/pi-agent.nix"
  assert_contains "$flake_text" "packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent"
  assert_contains "$flake_text" "shellcheck"
}

test_bash_runner_accepts_multiple_test_files() {
  local output
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" --no-docker test_utils.sh test_platform.sh 2>&1)"

  assert_contains "$output" "--- test_utils.sh ---"
  assert_contains "$output" "--- test_platform.sh ---"
}
