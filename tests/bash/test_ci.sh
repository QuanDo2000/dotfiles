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

  assert_equals 1 "$(grep -c 'run: nix develop \. -c bash \./tests/bash/runner\.sh$' <<< "$workflow")"
  assert_contains "$workflow" 'nix develop .#ci -c bash ./tests/bash/runner.sh test_cli.sh test_doctor.sh test_mac_install.sh test_neovim.sh test_tmux.sh'
  assert_not_contains "$workflow" 'runner.sh --no-docker'
  assert_not_contains "$workflow" 'docker'
}

test_ci_dev_shell_includes_script_dependencies() {
  local flake
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$flake" "jq"
  assert_contains "$flake" "cosign"
  assert_contains "$flake" 'LAZY_NVIM_PATH = "${pkgs.vimPlugins.lazy-nvim}";'
  assert_contains "$flake" 'devShells.aarch64-darwin.ci = ciShell darwinPkgs;'
  assert_contains "$flake" 'devShells.x86_64-linux.ci = ciShell linuxPkgs;'
  assert_contains "$flake" 'ciShell = pkgs: pkgs.mkShellNoCC {'
  assert_not_contains "$(sed -n '/ciShell =/,/^[[:space:]]*};/p' "$REPO_DIR/flake.nix")" 'pi-agent'
  assert_contains "$(<"$REPO_DIR/scripts/update_pins.py")" '"cosign", "verify-blob"'
  assert_not_contains "$(<"$REPO_DIR/scripts/update_pins.py")" '"nix", "develop", f"path:{repo}", "-c", "cosign"'
}

test_ci_runs_direct_nix_checks() {
  local workflow check
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"
  check="$(<"$REPO_DIR/scripts/check.sh")"

  assert_not_contains "$workflow" "run: ./scripts/check.sh"
  assert_contains "$workflow" "nix flake check --no-build --all-systems"
  assert_contains "$workflow" 'darwinConfigurations.mac.system.drvPath'
  assert_contains "$workflow" 'homeConfigurations.\"$username@linux\".activationPackage.drvPath'
  assert_contains "$workflow" 'homeConfigurations.\"$username@arch-server\".activationPackage.drvPath'
  assert_not_contains "$check" 'fff-nvim-backend'
}

test_ci_runs_windows_neovim_integration() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "Neovim.Neovim"
  assert_contains "$workflow" 'Microsoft\WinGet\Links\nvim.exe'
  assert_contains "$workflow" 'Neovim\bin\nvim.exe'
  assert_contains "$workflow" "tests/powershell/integration_neovim.ps1"
  assert_contains "$workflow" "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020"
  assert_contains "$workflow" "node-version: $(jq -r .node.version "$REPO_DIR/packages/pi-extensions-release.json")"
  assert_contains "$workflow" "tests/powershell/integration_pi_extensions.ps1"

  local integration
  integration="$(<"$REPO_DIR/tests/powershell/integration_neovim.ps1")"
  assert_contains "$integration" "dotfile.ps1"
  assert_contains "$integration" "Get-NeovimCommand"
  assert_contains "$integration" "XDG_CONFIG_HOME"
  assert_contains "$integration" "XDG_DATA_HOME"
  assert_contains "$integration" "Remove-Item -Recurse -Force"
}

test_ci_pins_current_actions() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
  assert_contains "$workflow" "actions/setup-node@820762786026740c76f36085b0efc47a31fe5020 # v7.0.0"
  assert_contains "$workflow" "DeterminateSystems/nix-installer-action@ef8a148080ab6020fd15196c2084a2eea5ff2d25 # v22"
  assert_contains "$workflow" $'permissions:\n  contents: read'
}

test_ci_checker_jobs_provision_dependencies() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_not_contains "${workflow,,}" "cspell"
  assert_not_contains "${workflow,,}" "codespell"
  assert_contains "$workflow" "nix develop . -c shellcheck"
  assert_not_contains "$(find "$REPO_DIR/.github/workflows" -maxdepth 1 -type f -name 'lint.*' -print)" 'lint.'
  assert_contains "$(<"$REPO_DIR/flake.nix")" "shellcheck"
}

test_ci_cancels_superseded_runs_and_bounds_jobs() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" 'cancel-in-progress: true'
  assert_equals 3 "$(grep -c 'timeout-minutes:' <<< "$workflow")"
}
