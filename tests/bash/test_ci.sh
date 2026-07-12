#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_ci_runs_direct_nix_checks() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_not_contains "$workflow" "run: ./scripts/check.sh"
  assert_contains "$workflow" "nix flake check --no-build --all-systems"
  assert_contains "$workflow" 'nix build .#codex .#obsidian-headless .#pi-agent .#fff-mcp --no-link'
}

test_ci_runs_windows_lazyvim_integration() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "Neovim.Neovim"
  assert_contains "$workflow" 'Microsoft\WinGet\Links\nvim.exe'
  assert_contains "$workflow" "tests/powershell/integration_lazyvim.ps1"

  local integration
  integration="$(<"$REPO_DIR/tests/powershell/integration_lazyvim.ps1")"
  assert_contains "$integration" "XDG_CONFIG_HOME"
  assert_contains "$integration" "XDG_DATA_HOME"
  assert_contains "$integration" "Remove-Item -Recurse -Force"
}

test_ci_pins_nix_installer_action() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "DeterminateSystems/nix-installer-action@v"
  assert_not_contains "$workflow" "DeterminateSystems/nix-installer-action@main"
}

test_lint_ci_uses_pinned_nix_shellcheck() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/lint.yml")"

  assert_contains "$workflow" "DeterminateSystems/nix-installer-action@v"
  assert_contains "$workflow" "nix develop . -c shellcheck"
}
