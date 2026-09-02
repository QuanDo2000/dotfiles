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

  assert_equals 0 "$(grep -c 'run: nix develop \. -c bash \./tests/bash/runner\.sh$' <<< "$workflow")"
  assert_contains "$workflow" $'  bash-linux:\n    needs: changes'
  assert_contains "$workflow" 'nix develop .#ci -c bash -c'
  assert_contains "$workflow" 'nix develop . -c bash -c'
  assert_equals 2 "$(grep -c 'neovim_pid=\$!' <<< "$workflow")"
  assert_equals 2 "$(grep -c 'core_pid=\$!' <<< "$workflow")"
  assert_contains "$workflow" 'test_cli.sh test_doctor.sh test_mac_install.sh test_tmux.sh'
  assert_contains "$workflow" 'tests_pid=$!'
  assert_contains "$workflow" 'darwin_pid=$!'
  assert_contains "$workflow" 'packages_pid=$!'
  assert_contains "$workflow" 'wait "$tests_pid"'
  assert_not_contains "$workflow" '- name: Evaluate nix-darwin configuration'
  assert_not_contains "$workflow" 'runner.sh --no-docker'
  assert_not_contains "$workflow" 'docker'
}

test_ci_filters_pull_requests_but_runs_full_main_and_schedule() {
  local workflow filter output
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"
  filter="$REPO_DIR/scripts/ci_paths.sh"

  assert_file_exists "$filter"
  [ -f "$filter" ] || return
  assert_not_contains "$workflow" 'dorny/paths-filter'
  assert_contains "$workflow" $'schedule:\n    - cron:'
  assert_contains "$workflow" "if: \${{ github.event_name == 'pull_request' }}"
  assert_contains "$workflow" 'fetch-depth: 0'
  assert_contains "$workflow" 'git diff --name-only --no-renames'
  assert_contains "$workflow" 'bash scripts/ci_paths.sh'
  assert_equals 4 "$(grep -c 'needs: changes' <<< "$workflow")"
  assert_equals 4 "$(grep -c "github.event_name != 'pull_request' || needs.changes.outputs" <<< "$workflow")"
  assert_contains "$workflow" "linux: \${{ steps.filter.outputs.linux }}"
  assert_contains "$workflow" "macos: \${{ steps.filter.outputs.macos }}"
  assert_contains "$workflow" "windows: \${{ steps.filter.outputs.windows }}"
  assert_contains "$workflow" "nix: \${{ steps.filter.outputs.nix }}"

  output="$(printf '%s\n' docs/note.md | bash "$filter")"
  assert_equals $'linux=false\nmacos=false\nwindows=false\nnix=false' "$output"
  output="$(printf '%s\n' dotfile.ps1 | bash "$filter")"
  assert_equals $'linux=true\nmacos=false\nwindows=true\nnix=false' "$output"
  output="$(printf '%s\n' config/darwin.nix | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=false\nnix=true' "$output"
  output="$(printf '%s\n' config/nixos-wsl/configuration.nix | bash "$filter")"
  assert_equals $'linux=true\nmacos=false\nwindows=false\nnix=true' "$output"
  output="$(printf '%s\n' config/shared/ai/AGENTS.md | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
  output="$(printf '%s\n' .gitattributes | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
}

test_ci_dev_shell_includes_script_dependencies() {
  local flake
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$flake" "jq"
  assert_contains "$flake" 'LAZY_NVIM_PATH = "${pkgs.vimPlugins.lazy-nvim}";'
  local dev_shell
  dev_shell="$(sed -n '/devShell =/,/^[[:space:]]*};/p' "$REPO_DIR/flake.nix")"
  assert_contains "$dev_shell" 'zsh'
  assert_contains "$flake" 'devShells.aarch64-darwin.ci = ciShell darwinPkgs;'
  assert_contains "$flake" 'devShells.x86_64-linux.ci = ciShell linuxPkgs;'
  assert_contains "$flake" 'ciShell = pkgs: pkgs.mkShellNoCC {'
  local ci_shell
  ci_shell="$(sed -n '/ciShell =/,/^[[:space:]]*};/p' "$REPO_DIR/flake.nix")"
  assert_contains "$ci_shell" 'python3'
  assert_contains "$ci_shell" 'tree-sitter'
  assert_not_contains "$ci_shell" 'pi-agent'
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

test_ci_avoids_disposable_neovim_cache_and_parallelizes_windows() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_equals 2 "$(grep -c 'DOTFILE_NEOVIM_TEST_CACHE=false bash ./tests/bash/runner.sh test_neovim.sh' <<< "$workflow")"
  assert_contains "$workflow" '- name: Run Windows checks in parallel'
  assert_contains "$workflow" 'Start-Job'
  assert_contains "$workflow" 'Wait-Job'
  assert_contains "$workflow" "'PowerShell tests'"
  assert_contains "$workflow" "'Pi extension integration'"
  assert_contains "$workflow" "'Neovim integration'"
  assert_not_contains "$workflow" '- name: Run PowerShell tests (Windows)'
  assert_not_contains "$workflow" '- name: Test locked Pi extensions (Windows)'
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
  assert_contains "$workflow" "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1"
  assert_equals 2 "$(grep -c 'cachix/cachix-action@5f2d7c5294214f71b873db4b969586b980625e71 # v17' <<< "$workflow")"
  assert_contains "$workflow" 'name: ${{ vars.CACHIX_CACHE_NAME }}'
  assert_contains "$workflow" "authToken: \${{ github.event_name == 'push' && github.ref == 'refs/heads/main' && secrets.CACHIX_AUTH_TOKEN || '' }}"
  assert_contains "$workflow" "skipPush: \${{ github.event_name != 'push' || github.ref != 'refs/heads/main' }}"
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
  assert_equals 5 "$(grep -c 'timeout-minutes:' <<< "$workflow")"
}
