#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_ci_runs_flake_check() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "run: ./scripts/check.sh"
}

test_ci_pins_nix_installer_action() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "DeterminateSystems/nix-installer-action@v"
  assert_not_contains "$workflow" "DeterminateSystems/nix-installer-action@main"
}
