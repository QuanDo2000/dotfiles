#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_ci_bash_jobs_match_local_nix_environment() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" 'nix develop . -c bash ./tests/bash/runner.sh --no-docker'
}

test_ci_dev_shell_includes_script_dependencies() {
  local flake
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$flake" "jq"
}

test_ci_runs_direct_nix_checks() {
  local workflow check
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"
  check="$(<"$REPO_DIR/scripts/check.sh")"

  assert_not_contains "$workflow" "run: ./scripts/check.sh"
  assert_contains "$workflow" "nix flake check --no-build --all-systems"
  assert_contains "$workflow" 'nix build .#codex .#obsidian-headless .#pi-agent .#fff-mcp .#fff-nvim-backend .#codebase-memory-mcp --no-link'
  assert_contains "$workflow" 'nix build .#fff-nvim-backend --no-link'
  assert_contains "$check" '"$repo_dir#fff-nvim-backend"'
}

test_ci_runs_windows_lazyvim_integration() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "Neovim.Neovim"
  assert_contains "$workflow" 'Microsoft\WinGet\Links\nvim.exe'
  assert_contains "$workflow" 'Neovim\bin\nvim.exe'
  assert_contains "$workflow" "tests/powershell/integration_lazyvim.ps1"

  local integration
  integration="$(<"$REPO_DIR/tests/powershell/integration_lazyvim.ps1")"
  assert_contains "$integration" "dotfile.ps1"
  assert_contains "$integration" "Get-NeovimCommand"
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

test_ci_checker_jobs_provision_dependencies() {
  local lint prefix workflows="" workflow
  lint="$(<"$REPO_DIR/.github/workflows/lint.yml")"

  shopt -s nullglob
  for workflow in "$REPO_DIR"/.github/workflows/*.{yml,yaml}; do
    workflows+="$(<"$workflow")"$'\n'
  done
  shopt -u nullglob

  assert_not_contains "${workflows,,}" "cspell"
  assert_not_contains "${workflows,,}" "codespell"
  assert_contains "$lint" "nix develop . -c shellcheck"
  prefix="${lint%%nix develop . -c shellcheck*}"
  assert_contains "$prefix" "DeterminateSystems/nix-installer-action@v"
  assert_contains "$(<"$REPO_DIR/flake.nix")" "shellcheck"
}
