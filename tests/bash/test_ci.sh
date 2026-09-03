#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_ci_bash_jobs_share_pinned_environments_and_parallelize_linux_checks() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" $'  bash-linux:\n    needs: changes'
  assert_contains "$workflow" 'nix develop .#ci -c bash ./tests/bash/runner.sh test_cli.sh test_doctor.sh test_mac_install.sh test_tmux.sh'
  assert_contains "$workflow" 'nix develop . -c bash -c'
  assert_equals 1 "$(grep -c 'neovim_pid=\$!' <<< "$workflow")"
  assert_equals 1 "$(grep -c 'core_pid=\$!' <<< "$workflow")"
  assert_equals 1 "$(grep -c 'shellcheck_pid=\$!' <<< "$workflow")"
  assert_contains "$workflow" 'wait "$shellcheck_pid"'
  assert_contains "$workflow" 'darwinConfigurations.mac.system.drvPath'
  assert_contains "$workflow" 'nix build .#codex .#pi-extensions --no-link'
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

test_ci_shards_windows_unit_tests_without_omissions() {
  local file workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_equals 3 "$(grep -c "Path = './tests/powershell/runner.ps1'" <<< "$workflow")"
  assert_contains "$workflow" "Arguments = @('test_ai_install.ps1', 'test_runner.ps1'"
  for file in "$REPO_DIR"/tests/powershell/test_*.ps1; do
    assert_equals 1 "$(grep -oF "'${file##*/}'" <<< "$workflow" | wc -l)"
  done
  assert_contains "$workflow" '$job.PSEndTime - $job.PSBeginTime'
}

test_ci_runs_direct_nix_checks_without_duplicate_home_evaluations() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "nix flake check --no-build --all-systems"
  assert_not_contains "$workflow" 'Evaluate Home Manager configurations'
  assert_not_contains "$workflow" 'homeConfigurations.\"$username@linux\".activationPackage.drvPath'
  assert_contains "$workflow" 'nix build .#codex .#obsidian-headless .#pi-agent .#pi-extensions --no-link'
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
  assert_contains "$workflow" "shellcheck -S warning"
  assert_not_contains "$(find "$REPO_DIR/.github/workflows" -maxdepth 1 -type f -name 'lint.*' -print)" 'lint.'
  assert_contains "$(<"$REPO_DIR/flake.nix")" "shellcheck"
}

test_ci_cancels_superseded_runs_and_bounds_jobs() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" 'cancel-in-progress: true'
  assert_equals 5 "$(grep -c 'timeout-minutes:' <<< "$workflow")"
}
