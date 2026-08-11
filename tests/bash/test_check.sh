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

  assert_contains "$check_text" 'nix develop "$flake" -c bash "$repo_dir/tests/bash/runner.sh" --no-docker'
  assert_contains "$check_text" 'nix develop "$flake" -c pwsh "$repo_dir/tests/powershell/runner.ps1"'
  assert_not_contains "$check_text" 'command -v pwsh'
  assert_contains "$check_text" 'nix flake check "$flake" --no-build --all-systems'
  assert_contains "$check_text" 'flake="path:$repo_dir"'
  assert_contains "$check_text" '"$flake#obsidian-headless"'
  assert_contains "$check_text" '"$flake#pi-agent"'
  assert_contains "$check_text" 'if [[ "$(uname -s)" == "Linux" ]]'
  assert_contains "$check_text" 'nix build "${packages[@]}" --no-link'
  assert_contains "$check_text" 'nix develop "$flake" -c shellcheck'
  assert_contains "$flake_text" "pi-agent = final.callPackage ./packages/pi-agent.nix"
  assert_contains "$flake_text" "fff-mcp = final.callPackage ./packages/fff-mcp.nix"
  assert_contains "$flake_text" "fff-nvim-backend = final.callPackage ./packages/fff-nvim-backend.nix"
  assert_contains "$flake_text" "codebase-memory-mcp = final.callPackage ./packages/codebase-memory-mcp.nix"
  assert_contains "$flake_text" "packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent"
  assert_contains "$flake_text" "packages.x86_64-linux.pi-extensions = linuxPkgs.pi-extensions"
  assert_contains "$flake_text" "packages.x86_64-linux.fff-mcp = linuxPkgs.fff-mcp"
  assert_contains "$flake_text" "packages.x86_64-linux.codebase-memory-mcp = linuxPkgs.codebase-memory-mcp"
  assert_contains "$flake_text" "devShells.aarch64-darwin.default"
  assert_contains "$flake_text" "python3"
  assert_contains "$flake_text" "shellcheck"
}

test_docker_test_environment_includes_python() {
  local runner_text
  runner_text="$(<"$REPO_DIR/tests/bash/runner.sh")"

  assert_contains "$runner_text" "python3"
}

test_bash_runner_accepts_multiple_test_files() {
  local output
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" --no-docker test_utils.sh test_platform.sh 2>&1)"

  assert_contains "$output" "--- test_utils.sh ---"
  assert_contains "$output" "--- test_platform.sh ---"
}
