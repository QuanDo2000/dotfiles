#!/usr/bin/env bash
# CI workflow coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_ci_workflow_preserves_routing_permissions_and_bounds() {
  python3 - "$REPO_DIR/.github/workflows/test.yml" <<'PY'
import sys
from pathlib import Path
import yaml
workflow = yaml.safe_load(Path(sys.argv[1]).read_text())
# PyYAML's YAML 1.1 loader reads the GitHub "on" key as boolean True.
events = workflow.get("on", workflow.get(True))
assert events["push"]["branches"] == ["deliver/**"]
assert events["pull_request"]["branches"] == ["main"]
assert events["schedule"]
assert workflow["permissions"] == {"contents": "read"}
assert workflow["concurrency"]["cancel-in-progress"] is True
jobs = workflow["jobs"]
platforms = {"bash-linux", "bash-macos", "powershell", "nix"}
assert set(jobs) == platforms | {"required-ci"}
for name in platforms:
    assert "needs" not in jobs[name] and "if" not in jobs[name], name
gate = jobs["required-ci"]
assert gate["name"] == "Required CI" and gate["if"] == "${{ always() }}"
assert set(gate["needs"]) == platforms
# Proprietary Rex outputs must predate the public cache's post-build hook.
mac_steps = jobs["bash-macos"]["steps"]
rex_step = next(i for i, step in enumerate(mac_steps) if step.get("name") == "Verify Rex package")
cache_step = next(i for i, step in enumerate(mac_steps) if step.get("uses", "").startswith("cachix/cachix-action@"))
assert rex_step < cache_step
assert mac_steps[cache_step]["with"]["useDaemon"] is True
for name, job in jobs.items():
    assert type(job["timeout-minutes"]) is int and job["timeout-minutes"] > 0, name
    expected_permissions = {} if name == "required-ci" else {"contents": "read"}
    assert job.get("permissions", workflow["permissions"]) == expected_permissions, name
    cache_steps = [step for step in job.get("steps", [])
                   if step.get("uses", "").startswith("cachix/cachix-action@")]
    if name in ("bash-linux", "bash-macos", "nix"):
        assert len(cache_steps) == 1, f"{name}: expected one shared Nix cache setup"
    for step in job.get("steps", []):
        if step.get("uses", "").startswith("cachix/cachix-action@"):
            options = step["with"]
            assert options["name"] == "${{ vars.CACHIX_CACHE_NAME }}"
            assert options["authToken"] == "${{ github.event_name == 'schedule' && secrets.CACHIX_AUTH_TOKEN || '' }}"
            assert options["skipPush"] == "${{ github.event_name != 'schedule' }}"
PY
}

test_required_ci_rejects_missing_or_failed_applicable_jobs() {
  python3 - "$REPO_DIR/.github/workflows/test.yml" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import yaml

jobs = yaml.safe_load(Path(sys.argv[1]).read_text())["jobs"]
gate = jobs["required-ci"]
assert set(gate["needs"]) == jobs.keys() - {"required-ci"}
step = gate["steps"][0]["run"]
bash = shutil.which("bash")
assert bash is not None
results = {name: {"result": "success"} for name in gate["needs"]}

def check(expected):
    completed = subprocess.run(
        [bash, "-e", "-o", "pipefail", "-c", step],
        env={**os.environ, "JOB_RESULTS": json.dumps(results)},
        capture_output=True, text=True, timeout=10,
    )
    assert completed.returncode == expected, (completed.stdout, completed.stderr)

check(0)
for job in gate["needs"]:
    for result in ("failure", "cancelled", "skipped"):
        results[job] = {"result": result}
        check(1)
    results[job] = {}
    check(1)
    del results[job]
    check(1)
    results[job] = {"result": "success"}
PY
}

test_ci_dev_shell_includes_script_dependencies() {
  local system default_shell ci_shell
  for system in x86_64-linux aarch64-darwin; do
    default_shell="$(command nix eval --json "path:$REPO_DIR#devShells.$system.default" --apply '
      shell: { packages = map (p: p.pname or (builtins.parseDrvName p.name).name) shell.nativeBuildInputs;
               lazy = builtins.toString shell.LAZY_NVIM_PATH; }
    ')"
    assert_equals true "$(jq '(["coreutils", "gh", "jq", "python3", "zsh", "rclone", "ShellCheck"] - .packages) | length == 0' <<< "$default_shell")"
    assert_contains "$(jq -r .lazy <<< "$default_shell")" '-vimplugin-lazy.nvim-'
    ci_shell="$(command nix eval --json "path:$REPO_DIR#devShells.$system.ci" --apply '
      shell: map (p: p.pname or (builtins.parseDrvName p.name).name) shell.nativeBuildInputs
    ')"
    assert_equals true "$(jq '((["python3", "tree-sitter"] - .) | length == 0) and (index("pi-coding-agent") == null)' <<< "$ci_shell")"
  done
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
