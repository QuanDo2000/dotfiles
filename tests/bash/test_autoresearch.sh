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

test_autoresearch_completion_summary_reports_best_result() {
  assert_file_exists "$extension_dir/metrics.ts"
  [ -f "$extension_dir/metrics.ts" ] || return
  METRICS="file://$extension_dir/metrics.ts" assert_exit_code 0 node --input-type=module - <<'JS'
const { formatCompletionSummary } = await import(process.env.METRICS);
const entries = [
  { status: "baseline", metric: 100 },
  { status: "discard", metric: 110 },
  { status: "keep", metric: 80 },
];
const summary = formatCompletionSummary(entries, "latency_ms", "lower", "/tmp/autoresearch-speed");
for (const expected of ["baseline latency_ms: 100", "best latency_ms: 80", "improvement: 20.00%", "accepted experiments: 1", "/tmp/autoresearch-speed"]) {
  if (!summary.includes(expected)) throw new Error(`missing summary field: ${expected}`);
}
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
check(await validatePilot(safe, { requireFiles: true, requireClean: false }) === null, "Linux bounded files rejected");
check(await validatePilot(safe, { requireFiles: true, requireClean: false, platform: "darwin" }) === null, "macOS bounded files rejected");
fs.writeFileSync(path.join(safe, ".auto/config.json"), JSON.stringify({ maxIterations: 21, metricName: "latency_ms", direction: "lower" }));
check((await validatePilot(safe, { requireFiles: true, requireClean: false }))?.includes("1 to 20"), "iteration overflow accepted");
fs.writeFileSync(path.join(safe, ".auto/config.json"), JSON.stringify({ maxIterations: 20, metricName: "latency_ms", direction: "lower" }));
fs.rmSync(path.join(safe, ".auto/checks.sh"));
fs.mkdirSync(path.join(safe, ".auto/checks.sh"));
check((await validatePilot(safe, { requireFiles: true, requireClean: false }))?.includes("regular executable file"), "checks directory accepted");
fs.rmSync(path.join(safe, ".auto/checks.sh"), { recursive: true });
fs.writeFileSync(path.join(safe, ".auto/checks.sh"), "#!/usr/bin/env bash\nexit 0\n", { mode: 0o755 });
fs.rmSync(path.join(safe, ".auto/measure.sh"));
fs.rmSync(path.join(safe, ".auto/checks.sh"));
fs.writeFileSync(path.join(safe, ".auto/measure.ps1"), "Write-Output 'METRIC latency_ms=1'\n");
fs.writeFileSync(path.join(safe, ".auto/checks.ps1"), "exit 0\n");
check(await validatePilot(safe, { requireFiles: true, requireClean: false, platform: "win32" }) === null, "Windows bounded files rejected");
const externalConfig = path.join(path.dirname(safe), "external-config.json");
fs.copyFileSync(path.join(safe, ".auto/config.json"), externalConfig);
fs.rmSync(path.join(safe, ".auto/config.json"));
fs.symlinkSync(externalConfig, path.join(safe, ".auto/config.json"));
check((await validatePilot(safe, { requireFiles: true, requireClean: false, platform: "win32" }))?.includes("config.json must be a regular file"), "config symlink accepted");
fs.rmSync(path.join(safe, ".auto/config.json"));
fs.copyFileSync(externalConfig, path.join(safe, ".auto/config.json"));
fs.mkdirSync(path.join(safe, ".auto/hooks"));
check((await validatePilot(safe, { requireFiles: true, requireClean: false, platform: "win32" }))?.includes("does not allow .auto/hooks"), "hooks accepted");
fs.rmSync(path.join(safe, ".auto"), { recursive: true });
const externalAuto = path.join(path.dirname(safe), "external-auto");
fs.mkdirSync(externalAuto);
fs.symlinkSync(externalAuto, path.join(safe, ".auto"), "dir");
check((await validatePilot(safe, { requireFiles: false, requireClean: false }))?.includes("regular directory"), ".auto symlink accepted");
check((await validatePilot(safe, { requireFiles: false, requireClean: false, platform: "freebsd" }))?.includes("Linux, macOS, and Windows"), "unsupported platform accepted");
JS
  SAFETY="file://$extension_dir/safety.ts" assert_exit_code 0 node "$TEST_TMPDIR/test-safety.mjs" "$root" "$wrong" "$safe"
}

test_autoresearch_runtime_selects_native_scripts_without_path_lookup() {
  assert_file_exists "$extension_dir/runtime.ts"
  [ -f "$extension_dir/runtime.ts" ] || return
  RUNTIME="file://$extension_dir/runtime.ts" assert_exit_code 0 node --input-type=module - <<'JS'
import path from "node:path";
const { scriptCommand } = await import(process.env.RUNTIME);
const root = path.resolve("work");
const linux = scriptCommand(root, "measure", "linux", {});
if (linux.command !== path.join(root, ".auto", "measure.sh") || linux.args.length !== 0) process.exit(1);
const mac = scriptCommand(root, "checks", "darwin", {});
if (mac.command !== path.join(root, ".auto", "checks.sh") || mac.args.length !== 0) process.exit(1);
const windows = scriptCommand(root, "measure", "win32", { SystemRoot: "C:\\Windows" });
if (windows.command !== path.win32.join("C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe")) process.exit(1);
if (windows.args.join("|") !== ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path.join(root, ".auto", "measure.ps1")].join("|")) process.exit(1);
let rejected = false;
try { scriptCommand(root, "measure", "win32", {}); } catch { rejected = true; }
if (!rejected) process.exit(1);
JS
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

test_autoresearch_workspace_helpers_create_suffix_and_remove() {
  assert_file_exists "$extension_dir/git.ts"
  assert_file_exists "$extension_dir/jj.ts"
  [ -f "$extension_dir/git.ts" ] && [ -f "$extension_dir/jj.ts" ] || return

  local git_root="$TEST_TMPDIR/create-git" jj_root="$TEST_TMPDIR/create-jj"
  git init -q "$git_root"
  git -C "$git_root" config user.name Test
  git -C "$git_root" config user.email test@example.invalid
  git -C "$git_root" config commit.gpgsign false
  echo baseline > "$git_root/input"
  git -C "$git_root" add input
  git -C "$git_root" commit -qm baseline

  jj git init "$jj_root" >/dev/null
  jj -R "$jj_root" config set --repo user.name Test
  jj -R "$jj_root" config set --repo user.email test@example.invalid
  echo baseline > "$jj_root/input"
  jj -R "$jj_root" commit -m baseline >/dev/null

  GIT_HELPERS="file://$extension_dir/git.ts" JJ_HELPERS="file://$extension_dir/jj.ts" assert_exit_code 0 node --input-type=module - "$git_root" "$jj_root" <<'JS'
import fs from "node:fs";
import path from "node:path";
const { createAutoresearchWorktree, removeAutoresearchWorktree, rollbackAutoresearchWorktree, runGit } = await import(process.env.GIT_HELPERS);
const { createAutoresearchWorkspace, removeAutoresearchWorkspace, runJj, stateAt } = await import(process.env.JJ_HELPERS);
const [gitRoot, jjRoot] = process.argv.slice(2);
const check = (condition, message) => { if (!condition) throw new Error(message); };

const occupied = path.join(path.dirname(gitRoot), "autoresearch-reduce-latency");
fs.symlinkSync(path.join(path.dirname(gitRoot), "missing-target"), occupied);
fs.writeFileSync(path.join(gitRoot, "dirty"), "dirty\n");
let dirtyRejected = false;
try { await createAutoresearchWorktree(gitRoot, "unsafe"); } catch (error) { dirtyRejected = String(error).includes("clean primary checkout"); }
check(dirtyRejected, "dirty Git primary checkout accepted");
fs.rmSync(path.join(gitRoot, "dirty"));
const gitFirst = await createAutoresearchWorktree(gitRoot, "reduce latency");
const gitSecond = await createAutoresearchWorktree(gitRoot, "reduce latency");
check(gitFirst.name === "autoresearch/reduce-latency-2", "dangling-link Git collision was not skipped");
check(gitSecond.name === "autoresearch/reduce-latency-3", "Git collision suffix missing");
fs.writeFileSync(path.join(gitFirst.path, "dirty"), "dirty\n");
let dirtyRemovalRejected = false;
try { await removeAutoresearchWorktree(gitRoot, gitFirst.path); } catch (error) { dirtyRemovalRejected = String(error).includes("dirty Git worktree"); }
check(dirtyRemovalRejected && fs.existsSync(gitFirst.path), "dirty Git worktree cleanup was not refused");
fs.rmSync(path.join(gitFirst.path, "dirty"));
await removeAutoresearchWorktree(gitRoot, gitFirst.path);
await removeAutoresearchWorktree(gitRoot, gitSecond.path);
check(!fs.existsSync(gitFirst.path) && !fs.existsSync(gitSecond.path), "Git worktree directory remains");
check((await runGit(gitRoot, ["branch", "--list", gitFirst.name])) === gitFirst.name, "Git cleanup deleted branch history");
const gitRollback = await createAutoresearchWorktree(gitRoot, "failed setup");
await rollbackAutoresearchWorktree(gitRoot, gitRollback);
check(!fs.existsSync(gitRollback.path), "Git rollback kept worktree path");
check((await runGit(gitRoot, ["branch", "--list", gitRollback.name])) === "", "Git rollback kept newly created branch");

fs.writeFileSync(path.join(jjRoot, "dirty"), "uncommitted\n");
let nonemptySourceRejected = false;
try { await createAutoresearchWorkspace(jjRoot, "unsafe"); } catch (error) { nonemptySourceRejected = String(error).includes("empty working-copy commit"); }
check(nonemptySourceRejected, "nonempty JJ source workspace accepted");
fs.rmSync(path.join(jjRoot, "dirty"));
const jjFirst = await createAutoresearchWorkspace(jjRoot, "reduce latency");
const jjSecond = await createAutoresearchWorkspace(jjRoot, "reduce latency");
check(jjFirst.name === "autoresearch-reduce-latency-2", "dangling-link JJ collision was not skipped");
check(jjSecond.name === "autoresearch-reduce-latency-3", "JJ collision suffix missing");
check((await stateAt(jjFirst.path)).empty && (await stateAt(jjSecond.path)).empty, "created JJ workspace is not empty");
await removeAutoresearchWorkspace(jjRoot, jjFirst);
await removeAutoresearchWorkspace(jjRoot, jjSecond);
check(!fs.existsSync(jjFirst.path) && !fs.existsSync(jjSecond.path), "JJ workspace directory remains");
const jjNames = await runJj(jjRoot, ["workspace", "list", "-T", 'name ++ "\\n"']);
check(!jjNames.includes(jjFirst.name) && !jjNames.includes(jjSecond.name), "JJ cleanup kept workspace registration");
check(fs.lstatSync(occupied).isSymbolicLink(), "collision handling removed unrelated sibling path");
JS
}

test_autoresearch_jj_guard_accepts_only_dedicated_empty_workspace() {
  assert_file_exists "$extension_dir/safety.ts"
  [ -f "$extension_dir/safety.ts" ] || return

  local root="$TEST_TMPDIR/jj-repo" work="$TEST_TMPDIR/jj-work"
  jj git init "$root" >/dev/null
  jj -R "$root" config set --repo user.name Test
  jj -R "$root" config set --repo user.email test@example.invalid
  echo baseline > "$root/input"
  jj -R "$root" commit -m baseline >/dev/null
  jj --quiet -R "$root" workspace add --name autoresearch-test -r @- "$work"

  SAFETY="file://$extension_dir/safety.ts" assert_exit_code 0 node --input-type=module - "$root" "$work" <<'JS'
import fs from "node:fs";
import path from "node:path";
const { validatePilot } = await import(process.env.SAFETY);
const [primary, work] = process.argv.slice(2);
const check = (condition, message) => { if (!condition) throw new Error(message); };
check((await validatePilot(primary, { requireFiles: false, requireClean: true }))?.includes("autoresearch-* workspace"), "primary JJ workspace accepted");
check(await validatePilot(work, { requireFiles: false, requireClean: true }) === null, "dedicated JJ workspace rejected");
const dirty = path.join(work, "dirty");
fs.writeFileSync(dirty, "change\n");
check((await validatePilot(work, { requireFiles: false, requireClean: true }))?.includes("empty JJ working-copy commit"), "nonempty JJ workspace accepted");
check(await validatePilot(work, { requireFiles: false, requireClean: false }) === null, "JJ experiment changes rejected");
fs.rmSync(dirty);
JS
}

test_autoresearch_jj_helpers_keep_and_discard_experiments() {
  assert_file_exists "$extension_dir/jj.ts"
  [ -f "$extension_dir/jj.ts" ] || return

  local root="$TEST_TMPDIR/jj-helper-repo" work="$TEST_TMPDIR/jj-helper-work"
  jj git init "$root" >/dev/null
  jj -R "$root" config set --repo user.name Test
  jj -R "$root" config set --repo user.email test@example.invalid
  echo baseline > "$root/input"
  jj -R "$root" commit -m baseline >/dev/null
  jj --quiet -R "$root" workspace add --name autoresearch-helper -r @- "$work"
  mkdir "$work/.auto"
  echo setup > "$work/.auto/log.jsonl"

  JJ_HELPERS="file://$extension_dir/jj.ts" assert_exit_code 0 node --input-type=module - "$work" <<'JS'
import fs from "node:fs";
import path from "node:path";
const { commitExperiment, fingerprintWorktree, isJjCommitId, restoreExperiment, revisionIdentity, runJj } = await import(process.env.JJ_HELPERS);
const cwd = process.argv[2];
const check = (condition, message) => { if (!condition) throw new Error(message); };
check(isJjCommitId("a".repeat(40)) && isJjCommitId("b".repeat(64)), "supported JJ commit ID rejected");
check(!isJjCommitId("a".repeat(39)) && !isJjCommitId("b".repeat(65)), "invalid JJ commit ID accepted");
const initialRevision = await revisionIdentity(cwd);
const initialTree = await fingerprintWorktree(cwd);
await runJj(cwd, ["describe", "-m", "unexpected metadata change"]);
check(await revisionIdentity(cwd) !== initialRevision, "JJ description change was not detected");
await runJj(cwd, ["describe", "-m", ""]);
const experimentRevision = await revisionIdentity(cwd);
fs.writeFileSync(path.join(cwd, "input"), "candidate\n");
fs.writeFileSync(path.join(cwd, "untracked"), "remove\n");
check(await fingerprintWorktree(cwd) !== initialTree, "JJ mutation was not detected");
check(await revisionIdentity(cwd) === experimentRevision, "working-copy content changed JJ revision identity");
await restoreExperiment(cwd);
check(fs.readFileSync(path.join(cwd, "input"), "utf8") === "baseline\n", "JJ tracked change not restored");
check(!fs.existsSync(path.join(cwd, "untracked")), "JJ added file not removed");
check(fs.existsSync(path.join(cwd, ".auto/log.jsonl")), "JJ .auto state removed");
fs.writeFileSync(path.join(cwd, "input"), "kept\n");
fs.appendFileSync(path.join(cwd, ".auto/log.jsonl"), "keep\n");
const kept = await commitExperiment(cwd, "keep", "faster");
check(isJjCommitId(kept), "JJ keep commit missing");
fs.writeFileSync(path.join(cwd, "input"), "discard\n");
fs.appendFileSync(path.join(cwd, ".auto/log.jsonl"), "discard\n");
await restoreExperiment(cwd);
await commitExperiment(cwd, "discard", "slower");
check(fs.readFileSync(path.join(cwd, "input"), "utf8") === "kept\n", "JJ discard kept experiment files");
check(fs.readFileSync(path.join(cwd, ".auto/log.jsonl"), "utf8").includes("discard"), "JJ discard lost durable log");
JS
}

test_autoresearch_extension_loads_commands() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local output="$TEST_TMPDIR/rpc.jsonl" errors="$TEST_TMPDIR/rpc.err" ordinary="$TEST_TMPDIR/ordinary-checkout" status=0
  git init -q "$ordinary"
  echo dirty > "$ordinary/untracked"
  (
    cd "$ordinary" || exit 1
    printf '%s\n' '{"id":"commands","type":"get_commands"}' |
      PI_OFFLINE=1 timeout 20 pi --mode rpc --no-extensions -e "$extension_dir/index.ts"
  ) >"$output" 2>"$errors" || status=$?
  assert_equals 0 "$status"
  assert_equals '' "$(<"$errors")"
  assert_exit_code 0 jq -se '
    any(.[]; .type == "response" and .id == "commands" and
      any(.data.commands[]; .name == "autoresearch") and
      any(.data.commands[]; .name == "skill:pi-autoresearch")) and
    all(.[]; .type != "agent_start")
  ' "$output"
}

test_autoresearch_command_creates_names_reports_and_cleans_git_worktree() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local root="$TEST_TMPDIR/git-auto-repo" work="$TEST_TMPDIR/autoresearch-reduce-latency"
  git init -q "$root"
  git -C "$root" config user.name Test
  git -C "$root" config user.email test@example.invalid
  git -C "$root" config commit.gpgsign false
  echo baseline > "$root/input"
  git -C "$root" add input
  git -C "$root" commit -qm baseline

  EXTENSION="$extension_dir/index.ts" ROOT="$root" WORK="$work" python3 - <<'PY' || echo '  automatic Git worktree QOL flow failed' >> "$ERROR_FILE"
import json
import os
import select
import shutil
import subprocess
import time

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--no-extensions", "-e", os.environ["EXTENSION"]],
    cwd=os.environ["ROOT"], env={**os.environ, "PI_OFFLINE": "1"},
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()
def read_until(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 1)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        event = json.loads(line)
        if predicate(event):
            return event
    raise RuntimeError("expected RPC event not observed")

send({"id": "auto", "type": "prompt", "message": "/autoresearch reduce latency"})
read_until(lambda event: event.get("type") == "extension_ui_request" and event.get("message") == "Autoresearch mode ON")
if not os.path.isfile(os.path.join(os.environ["WORK"], ".git")):
    raise RuntimeError("linked Git worktree was not created")

send({"id": "state", "type": "get_state"})
state = read_until(lambda event: event.get("type") == "response" and event.get("id") == "state")
if state.get("data", {}).get("sessionName") != "autoresearch: reduce latency":
    raise RuntimeError("autoresearch session was not named")

auto = os.path.join(os.environ["WORK"], ".auto")
os.mkdir(auto)
with open(os.path.join(auto, "config.json"), "w", encoding="utf-8") as file:
    json.dump({"maxIterations": 5, "metricName": "latency_ms", "direction": "lower"}, file)
with open(os.path.join(auto, "log.jsonl"), "w", encoding="utf-8") as file:
    file.write(json.dumps({"status": "baseline", "metric": 10}) + "\n")
    file.write(json.dumps({"status": "keep", "metric": 8}) + "\n")
send({"id": "status", "type": "prompt", "message": "/autoresearch status"})
status = read_until(lambda event: event.get("type") == "extension_ui_request" and "iterations: 2/5" in event.get("message", ""))
for expected in ["VCS: git", "best latency_ms: 8", "remaining: 3", os.environ["WORK"]]:
    if expected not in status["message"]:
        raise RuntimeError(f"status missing {expected}")
shutil.rmtree(auto)

send({"id": "cleanup", "type": "prompt", "message": "/autoresearch cleanup"})
confirm = read_until(lambda event: event.get("type") == "extension_ui_request" and event.get("method") == "confirm")
send({"type": "extension_ui_response", "id": confirm["id"], "confirmed": True})
read_until(lambda event: event.get("type") == "extension_ui_request" and "Removed Git worktree" in event.get("message", ""))
process.terminate()
process.wait(5)
errors = process.stderr.read()
if errors:
    raise RuntimeError(errors)
if os.path.exists(os.environ["WORK"]):
    raise RuntimeError("Git cleanup left worktree directory")
branch = subprocess.run(["git", "-C", os.environ["ROOT"], "branch", "--list", "autoresearch/reduce-latency"], check=True, capture_output=True, text=True).stdout.strip()
if branch != "autoresearch/reduce-latency":
    raise RuntimeError("Git cleanup deleted experiment branch")
PY
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

test_autoresearch_command_creates_and_enters_safe_jj_workspace() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local root="$TEST_TMPDIR/jj-auto-repo" work="$TEST_TMPDIR/autoresearch-reduce-latency"
  jj git init "$root" >/dev/null
  jj -R "$root" config set --repo user.name Test
  jj -R "$root" config set --repo user.email test@example.invalid
  echo baseline > "$root/input"
  jj -R "$root" commit -m baseline >/dev/null

  EXTENSION="$extension_dir/index.ts" ROOT="$root" WORK="$work" python3 - <<'PY' || echo '  automatic JJ workspace setup failed' >> "$ERROR_FILE"
import json
import os
import select
import subprocess
import time

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--no-extensions", "-e", os.environ["EXTENSION"]],
    cwd=os.environ["ROOT"], env={**os.environ, "PI_OFFLINE": "1"},
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
process.stdin.write(json.dumps({"id": "auto", "type": "prompt", "message": "/autoresearch reduce latency"}) + "\n")
process.stdin.flush()
found = False
deadline = time.monotonic() + 15
while time.monotonic() < deadline:
    ready, _, _ = select.select([process.stdout], [], [], 1)
    if not ready:
        continue
    line = process.stdout.readline()
    if not line:
        break
    event = json.loads(line)
    if event.get("type") == "extension_ui_request" and event.get("message") == "Autoresearch mode ON":
        found = True
        break
process.terminate()
process.wait(5)
errors = process.stderr.read()
if errors:
    raise SystemExit(errors)
if not found:
    raise SystemExit("automatic activation notification not observed")
if not os.path.isdir(os.path.join(os.environ["WORK"], ".jj")):
    raise SystemExit("dedicated JJ workspace was not created")
workspace_list = subprocess.run(
    ["jj", "--no-pager", "--color=never", "-R", os.environ["WORK"], "workspace", "list", "-T", 'name ++ "\\n"'],
    check=True, capture_output=True, text=True,
).stdout.splitlines()
if "autoresearch-reduce-latency" not in workspace_list:
    raise SystemExit("dedicated JJ workspace name missing")
PY
}

test_autoresearch_command_accepts_safe_jj_workspace() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return
  local root="$TEST_TMPDIR/jj-rpc-repo" work="$TEST_TMPDIR/jj-rpc-work"
  jj git init "$root" >/dev/null
  jj -R "$root" config set --repo user.name Test
  jj -R "$root" config set --repo user.email test@example.invalid
  echo baseline > "$root/input"
  jj -R "$root" commit -m baseline >/dev/null
  jj --quiet -R "$root" workspace add --name autoresearch-rpc -r @- "$work"

  EXTENSION="$extension_dir/index.ts" WORK="$work" python3 - <<'PY' || echo '  safe JJ activation failed' >> "$ERROR_FILE"
import json
import os
import select
import subprocess
import time

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--no-session", "--no-extensions", "-e", os.environ["EXTENSION"]],
    cwd=os.environ["WORK"], env={**os.environ, "PI_OFFLINE": "1"},
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
process.stdin.write(json.dumps({"id": "safe", "type": "prompt", "message": "/autoresearch reduce latency"}) + "\n")
process.stdin.flush()
found = False
deadline = time.monotonic() + 10
while time.monotonic() < deadline:
    ready, _, _ = select.select([process.stdout], [], [], 1)
    if not ready:
        continue
    event = json.loads(process.stdout.readline())
    if event.get("type") == "extension_ui_request" and event.get("message") == "Autoresearch mode ON":
        found = True
        break
process.terminate()
process.wait(5)
if process.stderr.read() or not found:
    raise SystemExit("safe JJ activation notification not observed")
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
