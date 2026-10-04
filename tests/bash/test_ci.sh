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
  assert_contains "$workflow" 'nix develop .#ci -c bash ./tests/bash/runner.sh test_cli.sh test_doctor.sh test_mac_install.sh test_tmux.sh test_release_pins.sh'
  assert_contains "$workflow" 'nix develop . -c bash -c'
  assert_equals 1 "$(grep -c 'neovim_pid=\$!' <<< "$workflow")"
  assert_equals 1 "$(grep -c 'core_pid=\$!' <<< "$workflow")"
  assert_equals 1 "$(grep -c 'shellcheck_pid=\$!' <<< "$workflow")"
  assert_contains "$workflow" 'wait "$shellcheck_pid"'
  assert_contains "$workflow" 'darwinConfigurations.mac.system.drvPath'
  assert_contains "$workflow" 'nix build .#pi-extensions --no-link'
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
  output="$(printf '%s\n' tests/bash/test_release_pins.sh | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=false\nnix=false' "$output"
  output="$(printf '%s\n' config/nixos-wsl/configuration.nix | bash "$filter")"
  assert_equals $'linux=true\nmacos=false\nwindows=false\nnix=true' "$output"
  output="$(printf '%s\n' config/shared/ai/AGENTS.md | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
  output="$(printf '%s\n' .gitattributes | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
}

test_ci_filters_known_platform_owned_paths_without_skipping_shared_consumers() {
  local filter="$REPO_DIR/scripts/ci_paths.sh" path output
  for path in scripts/google-drive-storage-sync.py scripts/input-method-status.sh packages/obsidian-headless.nix packages/webcord-release.nix packages/hyprsunset-status.nix rust/hyprsunset-status/src/main.rs tests/rust/hyprsunset_oracle.py config/unix/config/hypr/hyprland.lua; do
    output="$(printf '%s\n' "$path" | bash "$filter")"
    assert_equals $'linux=true\nmacos=false\nwindows=false\nnix=true' "$output"
  done
  for path in scripts/packages.sh scripts/check-update.sh scripts/update_pins.py packages/pi-extensions.nix tests/ai/pi-web-activation-smoke.mjs; do
    output="$(printf '%s\n' "$path" | bash "$filter")"
    assert_equals $'linux=true\nmacos=true\nwindows=false\nnix=true' "$output"
  done
  for path in scripts/patch_pi_compaction.py scripts/seed_merge/common.py packages/pi-agent.nix packages/pi-extensions-release.json config/shared/config/nvim/init.lua; do
    output="$(printf '%s\n' "$path" | bash "$filter")"
    assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
  done
  output="$(printf '%s\n' scripts/new-unknown.py | bash "$filter")"
  assert_equals $'linux=true\nmacos=true\nwindows=true\nnix=true' "$output"
  output="$(printf '%s\n' scripts/packages.sh scripts/seed_merge/pi.py | bash "$filter")"
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
  assert_contains "$dev_shell" 'rclone'
  assert_contains "$flake" 'devShells.aarch64-darwin.ci = ciShell darwinPkgs;'
  assert_contains "$flake" 'devShells.x86_64-linux.ci = ciShell linuxPkgs;'
  assert_contains "$flake" 'ciShell = pkgs: pkgs.mkShellNoCC {'
  local ci_shell
  ci_shell="$(sed -n '/ciShell =/,/^[[:space:]]*};/p' "$REPO_DIR/flake.nix")"
  assert_contains "$ci_shell" 'python3'
  assert_contains "$ci_shell" 'tree-sitter'
  assert_not_contains "$ci_shell" 'pi-agent'
}

test_ci_runs_direct_nix_checks_without_duplicate_home_evaluations() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"

  assert_contains "$workflow" "nix flake check --no-build --all-systems"
  assert_not_contains "$workflow" 'Evaluate Home Manager configurations'
  assert_not_contains "$workflow" 'homeConfigurations.\"$username@linux\".activationPackage.drvPath'
  assert_contains "$workflow" 'nix build .#obsidian-headless .#pi-agent .#pi-extensions --no-link'
}

test_ci_accepts_action_sha_refreshes() {
  local fixture="$TEST_TMPDIR/refreshed"
  mkdir -p "$fixture/.github/workflows"
  python3 - "$REPO_DIR/.github/workflows/test.yml" "$fixture/.github/workflows/test.yml" <<'PY'
import re
import sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
target.write_text(re.sub(r"@[0-9a-f]{40}", "@" + "a" * 40, source.read_text()))
PY
  (REPO_DIR="$fixture"; test_ci_pins_current_actions)
}

_ci_actions_pinned() {
  # Validate parsed step/job references, including flow mappings and scalars.
  # GitHub owns workflow schema validation; safe_load never executes YAML tags.
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path
import yaml

workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
references = []
for job in workflow["jobs"].values():
    if "uses" in job:
        references.append(job["uses"])
    references.extend(step["uses"] for step in job.get("steps", []) if "uses" in step)
if not references:
    raise ValueError("No action references found")
for reference in references:
    if isinstance(reference, str) and reference.startswith("./"):
        continue  # Local actions/workflows use the checked-out revision.
    if not isinstance(reference, str) or not re.fullmatch(r"[^\s@]+@[0-9a-fA-F]{40}", reference):
        raise ValueError(f"Action is not commit-pinned: {reference}")
PY
}

test_ci_pins_current_actions() {
  local workflow
  for workflow in "$REPO_DIR"/.github/workflows/*.yml "$REPO_DIR"/.github/workflows/*.yaml; do
    [[ -f "$workflow" ]] || continue
    _ci_actions_pinned "$workflow"
  done
}

test_ci_rejects_unpinned_external_actions() {
  local fixture="$TEST_TMPDIR/action.yml" reference
  for reference in actions/checkout@v7 actions/checkout@main "actions/checkout@$(printf 'a%.0s' {1..39})"; do
    printf 'on: push\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: %s\n' "$reference" > "$fixture"
    assert_exit_code 1 _ci_actions_pinned "$fixture"
  done
}

test_ci_rejects_inline_unpinned_actions() {
  local fixture="$TEST_TMPDIR/inline-action.yml"
  printf '%s\n' \
    'on: push' 'jobs:' '  check:' '    runs-on: ubuntu-latest' '    steps:' \
    '      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' \
    '      - { uses: actions/setup-node@v7 }' > "$fixture"
  assert_exit_code 1 _ci_actions_pinned "$fixture"
}

test_ci_accepts_yaml_action_layouts_and_local_actions() {
  local fixture="$TEST_TMPDIR/yaml-actions.yml"
  printf '%s\n' \
    'on: push' 'jobs:' '  check:' '    runs-on: ubuntu-latest' '    steps:' \
    '      - { "uses": "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" }' \
    '      - uses: >-' \
    '          actions/setup-node@820762786026740c76f36085b0efc47a31fe5020' \
    '      - { uses: "./local-action" }' > "$fixture"
  assert_exit_code 0 _ci_actions_pinned "$fixture"
}

test_ci_checks_reusable_workflow_references() {
  local fixture="$TEST_TMPDIR/reusable-workflow.yml"
  printf 'on: push\njobs:\n  call: { uses: owner/repo/.github/workflows/test.yml@main }\n' > "$fixture"
  assert_exit_code 1 _ci_actions_pinned "$fixture"
  printf 'on: push\njobs:\n  call: { uses: owner/repo/.github/workflows/test.yml@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa }\n' > "$fixture"
  assert_exit_code 0 _ci_actions_pinned "$fixture"
  printf 'on: push\njobs:\n  call: { uses: "./.github/workflows/test.yml" }\n' > "$fixture"
  assert_exit_code 0 _ci_actions_pinned "$fixture"
}

test_ci_restricts_cache_writes_and_permissions() {
  local workflow
  workflow="$(<"$REPO_DIR/.github/workflows/test.yml")"
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
