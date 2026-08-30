#!/usr/bin/env bash
# Hardened local Pi autoresearch extension tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

extension_dir="$REPO_DIR/config/shared/ai/pi/autoresearch"

test_autoresearch_metric_parser_accepts_only_structured_finite_numbers() {
  assert_file_exists "$extension_dir/metrics.ts"
  [ -f "$extension_dir/metrics.ts" ] || return
  METRICS="file://$extension_dir/metrics.ts" assert_exit_code 0 node --input-type=module - <<'JS'
const { isImprovement, parseMetrics } = await import(process.env.METRICS);
if (!isImprovement(9, [10, 11], "lower") || isImprovement(10, [10, 11], "lower")) process.exit(1);
if (!isImprovement(11, [9, 10], "higher") || isImprovement(10, [9, 10], "higher")) process.exit(1);
const parsed = parseMetrics("noise\nMETRIC latency_ms=12.5\nMETRIC throughput=1e3\nMETRIC bad=NaN\nMETRIC overflow=1e999\nMETRIC latency_ms=11\n");
if (JSON.stringify(parsed) !== JSON.stringify({ latency_ms: 11, throughput: 1000 })) process.exit(1);
if (Object.hasOwn(parsed, "constructor") || parsed.constructor !== undefined) process.exit(1);
JS
}

test_autoresearch_guard_rejects_unsafe_and_accepts_bounded_worktree() {
  assert_file_exists "$extension_dir/safety.ts"
  [ -f "$extension_dir/safety.ts" ] || return

  local root="$TEST_TMPDIR/repo" wrong="$TEST_TMPDIR/wrong" safe="$TEST_TMPDIR/safe"
  git init -q "$root"
  git -C "$root" config user.name Test
  git -C "$root" config user.email test@example.invalid
  git -C "$root" config commit.gpgsign false
  echo baseline > "$root/input"
  git -C "$root" add input
  git -C "$root" commit -qm baseline
  git -C "$root" worktree add -q -b wrong-branch "$wrong"
  git -C "$root" worktree add -q -b autoresearch/safe "$safe"

  cat > "$TEST_TMPDIR/test-safety.mjs" <<'JS'
import fs from "node:fs";
import path from "node:path";
const { validatePilot } = await import(process.env.SAFETY);
const [ordinary, wrong, safe] = process.argv.slice(2);
const check = (condition, message) => { if (!condition) throw new Error(message); };
check((await validatePilot(ordinary, { requireFiles: false, requireClean: true }))?.includes("linked Git worktree"), "ordinary checkout accepted");
check((await validatePilot(wrong, { requireFiles: false, requireClean: true }))?.includes("autoresearch/* branch"), "wrong branch accepted");
check(await validatePilot(safe, { requireFiles: false, requireClean: true }) === null, "safe activation rejected");
fs.mkdirSync(path.join(safe, ".auto"));
fs.writeFileSync(path.join(safe, ".auto/config.json"), JSON.stringify({ maxIterations: 20, metricName: "latency_ms", direction: "lower" }));
fs.writeFileSync(path.join(safe, ".auto/measure.sh"), "#!/usr/bin/env bash\necho METRIC latency_ms=1\n");
fs.writeFileSync(path.join(safe, ".auto/checks.sh"), "#!/usr/bin/env bash\nexit 0\n");
fs.chmodSync(path.join(safe, ".auto/measure.sh"), 0o755);
fs.chmodSync(path.join(safe, ".auto/checks.sh"), 0o755);
check(await validatePilot(safe, { requireFiles: true, requireClean: false }) === null, "bounded files rejected");
fs.writeFileSync(path.join(safe, ".auto/config.json"), JSON.stringify({ maxIterations: 21, metricName: "latency_ms", direction: "lower" }));
check((await validatePilot(safe, { requireFiles: true, requireClean: false }))?.includes("1 to 20"), "iteration overflow accepted");
fs.writeFileSync(path.join(safe, ".auto/config.json"), JSON.stringify({ maxIterations: 20, metricName: "latency_ms", direction: "lower" }));
fs.rmSync(path.join(safe, ".auto/checks.sh"));
fs.mkdirSync(path.join(safe, ".auto/checks.sh"));
check((await validatePilot(safe, { requireFiles: true, requireClean: false }))?.includes("regular executable file"), "checks directory accepted");
fs.rmSync(path.join(safe, ".auto/checks.sh"), { recursive: true });
fs.writeFileSync(path.join(safe, ".auto/checks.sh"), "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
fs.mkdirSync(path.join(safe, ".auto/hooks"));
check((await validatePilot(safe, { requireFiles: true, requireClean: false }))?.includes("does not allow .auto/hooks"), "hooks accepted");
const platform = Object.getOwnPropertyDescriptor(process, "platform");
Object.defineProperty(process, "platform", { value: "win32" });
check((await validatePilot(safe, { requireFiles: false, requireClean: false }))?.includes("only on Linux"), "non-Linux accepted");
Object.defineProperty(process, "platform", platform);
JS
  SAFETY="file://$extension_dir/safety.ts" assert_exit_code 0 node "$TEST_TMPDIR/test-safety.mjs" "$root" "$wrong" "$safe"
}

test_autoresearch_git_helpers_revert_only_experiment_and_fail_closed_on_commit() {
  assert_file_exists "$extension_dir/git.ts"
  [ -f "$extension_dir/git.ts" ] || return

  local root="$TEST_TMPDIR/git-repo" work="$TEST_TMPDIR/git-work"
  git init -q "$root"
  git -C "$root" config user.name Test
  git -C "$root" config user.email test@example.invalid
  git -C "$root" config commit.gpgsign false
  echo baseline > "$root/input"
  git -C "$root" add input
  git -C "$root" commit -qm baseline
  git -C "$root" worktree add -q -b autoresearch/git "$work"
  mkdir -p "$work/.auto"
  echo '{"maxIterations":5,"metricName":"latency_ms","direction":"lower"}' > "$work/.auto/config.json"
  echo setup > "$work/.auto/log.jsonl"
  git -C "$work" add .auto
  git -C "$work" commit -qm setup

  cat > "$TEST_TMPDIR/test-git.mjs" <<'JS'
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
const { commitExperiment, fingerprintWorktree, restoreExperiment } = await import(process.env.GIT_HELPERS);
const cwd = process.argv[2];
const check = (condition, message) => { if (!condition) throw new Error(message); };
const git = (...args) => spawnSync("git", args, { cwd, encoding: "utf8" });
const cleanTree = await fingerprintWorktree(cwd);
fs.writeFileSync(path.join(cwd, "input"), "candidate\n");
fs.writeFileSync(path.join(cwd, "untracked"), "remove\n");
fs.writeFileSync(path.join(cwd, ".auto/ideas.md"), "preserve\n");
check(await fingerprintWorktree(cwd) !== cleanTree, "working-tree mutation was not detected");
await restoreExperiment(cwd);
check(fs.readFileSync(path.join(cwd, "input"), "utf8") === "baseline\n", "tracked change not restored");
check(!fs.existsSync(path.join(cwd, "untracked")), "untracked experiment file not removed");
check(fs.existsSync(path.join(cwd, ".auto/ideas.md")), ".auto state removed");
fs.rmSync(path.join(cwd, ".auto/ideas.md"));
fs.writeFileSync(path.join(cwd, "input"), "kept\n");
fs.appendFileSync(path.join(cwd, ".auto/log.jsonl"), "keep\n");
const kept = await commitExperiment(cwd, "keep", "faster");
check(/^[0-9a-f]{40}$/.test(kept), "keep commit missing");
check(git("status", "--porcelain").stdout === "", "keep left dirty state");
const gpgMarker = path.join(cwd, ".gpg-called");
const gpgStub = path.join(cwd, ".gpg-stub");
fs.writeFileSync(gpgStub, `#!/bin/sh\necho called > '${gpgMarker}'\nexit 1\n`, { mode: 0o755 });
check(git("config", "commit.gpgsign", "true").status === 0, "could not enable signing");
check(git("config", "user.signingkey", "test-key").status === 0, "could not set signing key");
check(git("config", "gpg.program", gpgStub).status === 0, "could not set GPG stub");
fs.writeFileSync(path.join(cwd, "input"), "failed\n");
fs.appendFileSync(path.join(cwd, ".auto/log.jsonl"), "failed\n");
let failed = false;
try { await commitExperiment(cwd, "keep", "must fail"); } catch { failed = true; }
check(failed, "commit failure accepted");
check(fs.existsSync(gpgMarker), "signed commit path was bypassed");
check(git("config", "--bool", "commit.gpgsign").stdout.trim() === "true", "commit helper disabled signing");
check(git("diff", "--cached", "--quiet").status === 0, "failed commit left staged changes");
check(git("status", "--porcelain").stdout.includes("input"), "failed commit discarded experiment changes");
JS
  GIT_HELPERS="file://$extension_dir/git.ts" assert_exit_code 0 node "$TEST_TMPDIR/test-git.mjs" "$work"
}

test_autoresearch_extension_loads_and_rejects_ordinary_checkout() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local output="$TEST_TMPDIR/rpc.jsonl" errors="$TEST_TMPDIR/rpc.err" status=0
  printf '%s\n' \
    '{"id":"commands","type":"get_commands"}' \
    '{"id":"unsafe","type":"prompt","message":"/autoresearch test"}' |
    PI_OFFLINE=1 timeout 20 pi --mode rpc --no-session --no-extensions -e "$extension_dir/index.ts" >"$output" 2>"$errors" || status=$?
  assert_equals 0 "$status"
  assert_equals '' "$(<"$errors")"
  assert_exit_code 0 jq -se '
    any(.[]; .type == "response" and .id == "commands" and
      any(.data.commands[]; .name == "autoresearch") and
      any(.data.commands[]; .name == "skill:pi-autoresearch")) and
    any(.[]; .type == "extension_ui_request" and .method == "notify" and (.message | contains("linked Git worktree"))) and
    all(.[]; .type != "agent_start")
  ' "$output"
}

test_autoresearch_command_accepts_safe_linked_worktree() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local root="$TEST_TMPDIR/rpc-repo" work="$TEST_TMPDIR/rpc-work"
  git init -q "$root"
  git -C "$root" config user.name Test
  git -C "$root" config user.email test@example.invalid
  git -C "$root" config commit.gpgsign false
  echo baseline > "$root/input"
  git -C "$root" add input
  git -C "$root" commit -qm baseline
  git -C "$root" worktree add -q -b autoresearch/rpc "$work"

  EXTENSION="$extension_dir/index.ts" WORK="$work" python3 - <<'PY' || echo '  safe activation failed' >> "$ERROR_FILE"
import json
import os
import select
import subprocess
import time

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--no-session", "--no-extensions", "-e", os.environ["EXTENSION"]],
    cwd=os.environ["WORK"],
    env={**os.environ, "PI_OFFLINE": "1"},
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
process.stdin.write(json.dumps({"id": "safe", "type": "prompt", "message": "/autoresearch reduce latency"}) + "\n")
process.stdin.flush()
found = False
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    ready, _, _ = select.select([process.stdout], [], [], 1)
    if not ready:
        continue
    line = process.stdout.readline()
    if not line:
        break
    event = json.loads(line)
    if event.get("type") == "extension_ui_request" and event.get("method") == "notify" and event.get("message") == "Autoresearch mode ON":
        found = True
        break
process.terminate()
try:
    process.wait(5)
except subprocess.TimeoutExpired:
    process.kill()
    process.wait()
errors = process.stderr.read()
if errors:
    raise SystemExit(errors)
if not found:
    raise SystemExit("safe activation notification not observed")
PY
}

test_autoresearch_uses_no_upstream_runtime_package() {
  assert_equals false "$(jq '.dependencies | has("pi-autoresearch")' "$REPO_DIR/config/shared/ai/pi/extensions/package.json")"
  assert_equals 0 "$(jq '[.packages[] | (if type == "string" then . else .source end) | select(contains("pi-autoresearch"))] | length' "$REPO_DIR/config/shared/ai/pi/settings.json")"
  assert_equals false "$([[ -e "$REPO_DIR/scripts/patch_pi_autoresearch.py" ]] && echo true || echo false)"
}

test_autoresearch_agent_policy_suggests_but_never_autostarts() {
  local agents
  agents="$(<"$REPO_DIR/config/shared/ai/AGENTS.md")"
  assert_contains "$agents" 'suggest the bounded autoresearch workflow'
  assert_contains "$agents" 'Never start autoresearch without explicit user approval'
}
