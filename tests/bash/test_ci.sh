#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

# Execute the real Bash job blocks, substituting only costly tool boundaries.
# debt: replay supports unconditional Bash run steps; extend it if these jobs
# gain per-step conditions, environment overrides, or another shell.
_ci_run_job() (
  local job="$1" root="$2"
  nix() {
    printf 'nix %s\n' "$*" >> "$CI_CALLS"
    if [[ "$1" == develop && "$3" == -c ]]; then
      shift 3
      "$@"
    else
      [[ "$1" != "$CI_FAIL" ]]
    fi
  }
  shellcheck() {
    printf 'shellcheck %s\n' "$*" >> "$CI_CALLS"
    [[ "$CI_FAIL" != shellcheck ]]
  }
  export -f nix shellcheck
  python3 - "$REPO_DIR/.github/workflows/test.yml" "$job" > "$root/job.sh" <<'PY' || exit 1
import sys
from pathlib import Path
import yaml
job = yaml.safe_load(Path(sys.argv[1]).read_text())["jobs"][sys.argv[2]]
print("\n".join(step["run"] for step in job["steps"] if "run" in step))
PY
  cd "$root" || exit 1
  bash -e -o pipefail job.sh
)

test_ci_bash_jobs_use_pinned_tools_and_propagate_each_failure() {
  local root="$TEST_TMPDIR/ci" job failure failures
  export CI_CALLS="$TEST_TMPDIR/ci-calls" CI_FAIL=
  mkdir -p "$root/tests/bash"
  touch "$root/tests/bash/test_neovim.sh" "$root/tests/bash/test_core.sh"
  cat > "$root/tests/bash/runner.sh" <<'SH'
printf 'tests %s\n' "$*" >> "$CI_CALLS"
kind=core
[[ "$1" != test_neovim.sh ]] || kind=neovim
[[ "$CI_FAIL" != tests && "$CI_FAIL" != "$kind" ]]
SH
  for job in bash-linux bash-macos nix; do
    CI_FAIL=; : > "$CI_CALLS"
    assert_exit_code 0 _ci_run_job "$job" "$root"
    local calls
    calls="$(<"$CI_CALLS")"
    case "$job" in
      bash-linux)
        assert_contains "$calls" 'nix develop . -c bash'
        assert_contains "$calls" 'shellcheck -S warning'
        assert_contains "$calls" 'tests test_neovim.sh'
        assert_contains "$calls" 'tests test_core.sh'
        failures='shellcheck neovim core' ;;
      bash-macos)
        assert_contains "$calls" 'nix develop .#ci -c bash'
        assert_contains "$calls" 'nix eval --raw .#darwinConfigurations.mac.system.drvPath'
        assert_contains "$calls" 'nix build .#pi-extensions --no-link'
        failures='tests eval build' ;;
      nix)
        assert_contains "$calls" 'nix flake check --no-build --all-systems'
        assert_contains "$calls" 'nix build .#obsidian-headless .#pi-agent .#pi-extensions --no-link'
        failures='flake build' ;;
    esac
    for failure in $failures; do
      CI_FAIL="$failure"
      assert_exit_code 1 _ci_run_job "$job" "$root"
    done
  done
}

test_ci_workflow_preserves_routing_permissions_and_bounds() {
  python3 - "$REPO_DIR/.github/workflows/test.yml" <<'PY'
import sys
from pathlib import Path
import yaml
workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
# PyYAML's YAML 1.1 loader reads the GitHub "on" key as boolean True.
events = workflow.get("on", workflow.get(True))
assert events["push"]["branches"] == ["main"]
assert events["pull_request"]["branches"] == ["main"]
assert events["schedule"]
assert workflow["permissions"] == {"contents": "read"}
assert workflow["concurrency"]["cancel-in-progress"] is True
jobs = workflow["jobs"]
for name, output in (("bash-linux", "linux"), ("bash-macos", "macos"),
                     ("powershell", "windows"), ("nix", "nix")):
    job = jobs[name]
    needs = job["needs"]
    assert "changes" in (needs if isinstance(needs, list) else [needs]), name
    assert job["if"] == "${{ github.event_name != 'pull_request' || needs.changes.outputs." + output + " == 'true' }}", name
    assert jobs["changes"]["outputs"][output] == "${{ steps.filter.outputs." + output + " }}", output
steps = jobs["changes"]["steps"]
checkout = next(step for step in steps if step.get("uses", "").startswith("actions/checkout@"))
filter_step = next(step for step in steps if step.get("id") == "filter")
assert checkout["with"]["fetch-depth"] == 0
for step in (checkout, filter_step):
    assert step["if"] == "${{ github.event_name == 'pull_request' }}"
for variable, expression in (("BASE_SHA", "${{ github.event.pull_request.base.sha }}"),
                             ("HEAD_SHA", "${{ github.event.pull_request.head.sha }}")):
    assert filter_step["env"][variable] == expression, variable
for name, job in jobs.items():
    assert type(job["timeout-minutes"]) is int and job["timeout-minutes"] > 0, name
    assert job.get("permissions", workflow["permissions"]) == {"contents": "read"}, name
    for step in job.get("steps", []):
        if step.get("uses", "").startswith("cachix/cachix-action@"):
            options = step["with"]
            assert options["name"] == "${{ vars.CACHIX_CACHE_NAME }}"
            assert options["authToken"] == "${{ github.event_name == 'push' && github.ref == 'refs/heads/main' && secrets.CACHIX_AUTH_TOKEN || '' }}"
            assert options["skipPush"] == "${{ github.event_name != 'push' || github.ref != 'refs/heads/main' }}"
PY
}

test_ci_filters_pull_requests_but_runs_full_main_and_schedule() {
  local filter output
  filter="$REPO_DIR/scripts/ci_paths.sh"

  assert_file_exists "$filter"
  [ -f "$filter" ] || return
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
  local system default_shell ci_shell
  for system in x86_64-linux aarch64-darwin; do
    default_shell="$(command nix eval --json "path:$REPO_DIR#devShells.$system.default" --apply '
      shell: { packages = map (p: p.pname or (builtins.parseDrvName p.name).name) shell.nativeBuildInputs;
               lazy = builtins.toString shell.LAZY_NVIM_PATH; }
    ')"
    assert_equals true "$(jq '(["jq", "python3", "zsh", "rclone", "ShellCheck"] - .packages) | length == 0' <<< "$default_shell")"
    assert_contains "$(jq -r .lazy <<< "$default_shell")" '-vimplugin-lazy.nvim-'
    ci_shell="$(command nix eval --json "path:$REPO_DIR#devShells.$system.ci" --apply '
      shell: map (p: p.pname or (builtins.parseDrvName p.name).name) shell.nativeBuildInputs
    ')"
    assert_equals true "$(jq '((["python3", "tree-sitter"] - .) | length == 0) and (index("pi-coding-agent") == null)' <<< "$ci_shell")"
  done
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
