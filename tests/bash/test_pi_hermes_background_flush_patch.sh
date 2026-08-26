#!/usr/bin/env bash
# Pi Hermes detached shutdown flush patch tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

write_unpatched_fixture() {
  local root="$1"
  mkdir -p "$root/src/handlers"
  cat > "$root/src/handlers/session-flush.ts" <<'EOF'
import { execChildPrompt, resolveChildPiModel } from "./pi-child-process.js";

  async function flush(
    ctx: Pick<ExtensionContext, "sessionManager" | "model" | "modelRegistry" | "cwd">,
    signal?: AbortSignal,
    timeoutMs = 30000,
  ): Promise<void> {
    if (userTurnCount < config.flushMinTurns) return;

    if (usesDirectTransport(config)) {
      try {
        const directResult = await runDirect();
        if (directResult.ok) return;
      } catch {
        // Fall through to subprocess below.
      }
    }

    try {
      await execChildPrompt(pi, flushMessage, config, {
        cwd: ctx.cwd,
        model: resolveChildPiModel(ctx.model),
        signal,
        timeoutMs,
      });
    } catch {
      // Best-effort flush — never block compaction or shutdown.
    }
  }

  pi.on("session_shutdown", async (_event, ctx) => {
    if (!config.flushOnShutdown) return;
    await flush(ctx, undefined, 10000);
  });
EOF
  cat > "$root/src/handlers/pi-child-process.ts" <<'EOF'
import { existsSync, readFileSync, readdirSync } from "node:fs";
import * as fs from "node:fs/promises";

export async function execChildPrompt(
  pi: Pick<ExtensionAPI, "exec">,
EOF
  cat > "$root/src/handlers/child-process-watchdog.mjs" <<'EOF'
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

const [timeoutValue, cancellationPath, command, ...args] = process.argv.slice(2);
const timeoutMs = Number(timeoutValue);

if (!cancellationPath || !command || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  process.stderr.write("pi-hermes-memory watchdog: invalid invocation\n");
  process.exit(2);
}

const child = spawn(command, args, {
  detached: process.platform !== "win32",
  stdio: ["ignore", "pipe", "pipe"],
});
let timedOut = false;
let cancelled = false;
let forceTimer;
const timeout = setTimeout(() => { timedOut = true; }, timeoutMs);
const cancellationPoll = undefined;

child.once("error", (error) => {
  clearTimeout(timeout);
  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);
  process.stderr.write(`pi-hermes-memory watchdog: ${error.message}\n`);
  process.exitCode = timedOut ? 124 : cancelled ? 143 : 127;
});

child.once("close", (code, signal) => {
  clearTimeout(timeout);
  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);
  if (timedOut) {
    process.exitCode = 124;
  } else if (cancelled) {
    process.exitCode = 143;
  } else if (typeof code === "number") {
    process.exitCode = code;
  } else {
    process.exitCode = signal === "SIGTERM" ? 143 : 1;
  }
});
EOF
}

test_pi_hermes_patch_detaches_shutdown_flush() {
  local root="$TEST_TMPDIR/pi-hermes-memory"
  write_unpatched_fixture "$root"

  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>>"$ERROR_FILE"

  assert_contains "$(<"$root/src/handlers/session-flush.ts")" 'execDetachedChildPrompt'
  assert_contains "$(<"$root/src/handlers/session-flush.ts")" 'await execDetachedChildPrompt(pi, flushMessage'
  assert_not_contains "$(<"$root/src/handlers/session-flush.ts")" 'await flush(ctx, undefined, 10000);'
  assert_contains "$(<"$root/src/handlers/pi-child-process.ts")" 'export async function execDetachedChildPrompt('
  assert_contains "$(<"$root/src/handlers/pi-child-process.ts")" 'detached: true'
  assert_contains "$(<"$root/src/handlers/pi-child-process.ts")" 'child.unref();'
  assert_contains "$(<"$root/src/handlers/child-process-watchdog.mjs")" '"--cleanup-dir"'
  assert_contains "$(<"$root/src/handlers/child-process-watchdog.mjs")" 'rmSync(cleanupDir, { recursive: true, force: true })'
}

test_pi_hermes_watchdog_hides_child_window() {
  local root="$TEST_TMPDIR/pi-hermes-memory" watchdog
  write_unpatched_fixture "$root"

  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>>"$ERROR_FILE"
  watchdog="$(<"$root/src/handlers/child-process-watchdog.mjs")"

  assert_contains "$watchdog" $'const child = spawn(command, args, {\n  detached: process.platform !== "win32",\n  stdio: ["ignore", "pipe", "pipe"],\n  windowsHide: true,\n});'
}

test_pi_hermes_watchdog_removes_private_prompt_after_child_exit() {
  local root="$TEST_TMPDIR/pi-hermes-memory" prompt_dir
  write_unpatched_fixture "$root"
  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>>"$ERROR_FILE"
  prompt_dir="$(mktemp -d "${TMPDIR:-/tmp}/pi-hermes-prompt-test.XXXXXX")"
  printf '%s\n' secret > "$prompt_dir/prompt.md"

  node "$root/src/handlers/child-process-watchdog.mjs" 1000 - --cleanup-dir "$prompt_dir" node -e 'process.exit(0)' 2>>"$ERROR_FILE"

  if [ -e "$prompt_dir" ]; then
    printf 'prompt directory was not removed: %s\n' "$prompt_dir" >> "$ERROR_FILE"
    return 1
  fi
}

test_pi_hermes_patch_is_idempotent() {
  local root="$TEST_TMPDIR/pi-hermes-memory" before after
  write_unpatched_fixture "$root"

  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>>"$ERROR_FILE"
  before="$(find "$root" -type f -print0 | sort -z | xargs -0 sha256sum)"
  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>>"$ERROR_FILE"
  after="$(find "$root" -type f -print0 | sort -z | xargs -0 sha256sum)"

  assert_equals "$before" "$after"
}

test_pi_hermes_patch_rejects_source_drift_atomically() {
  local root="$TEST_TMPDIR/pi-hermes-memory" before after status=0
  write_unpatched_fixture "$root"
  printf '%s\n' 'upstream changed' > "$root/src/handlers/child-process-watchdog.mjs"
  before="$(find "$root" -type f -print0 | sort -z | xargs -0 sha256sum)"

  python3 "$REPO_DIR/scripts/patch_pi_hermes_background_flush.py" "$root" 2>"$TEST_TMPDIR/patch-error" || status=$?
  after="$(find "$root" -type f -print0 | sort -z | xargs -0 sha256sum)"

  assert_equals 1 "$status"
  assert_contains "$(<"$TEST_TMPDIR/patch-error")" 'Pi Hermes background flush patch source drift'
  assert_equals "$before" "$after"
}
