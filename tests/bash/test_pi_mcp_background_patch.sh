#!/usr/bin/env bash
# Pi MCP background startup patch tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

write_unpatched_fixture() {
  cat > "$1" <<'EOF'
    // Start all eager servers concurrently
    await Promise.allSettled(
      eagerServers.map(async ([name]) => {
        try {
          await manager.startServer(name, ctx.cwd);
        } catch (err) {
          const msg = err instanceof McpError ? err.userMessage : String(err);
          ctx.ui.notify(`pi-mcp: Failed to start ${name} — ${msg}`, "error");
        }
      }),
    );
EOF
}

test_pi_mcp_patch_waits_only_in_subagents() {
  local target="$TEST_TMPDIR/index.ts"
  write_unpatched_fixture "$target"

  python3 "$REPO_DIR/scripts/patch_pi_mcp_background.py" "$target" 2>>"$ERROR_FILE"

  assert_contains "$(<"$target")" '// Child sessions wait so strict tool allowlists see every eager MCP tool.'
  assert_contains "$(<"$target")" 'const eagerStartup = Promise.allSettled('
  assert_contains "$(<"$target")" 'if (process.env.PI_SUBAGENT_DEPTH) await eagerStartup;'
  assert_not_contains "$(<"$target")" 'await Promise.allSettled('
}

test_pi_mcp_patch_is_idempotent() {
  local target="$TEST_TMPDIR/index.ts" before
  write_unpatched_fixture "$target"

  python3 "$REPO_DIR/scripts/patch_pi_mcp_background.py" "$target" 2>>"$ERROR_FILE"
  before="$(sha256sum "$target")"
  python3 "$REPO_DIR/scripts/patch_pi_mcp_background.py" "$target" 2>>"$ERROR_FILE"

  assert_equals "$before" "$(sha256sum "$target")"
}

test_pi_mcp_patch_rejects_source_drift() {
  local target="$TEST_TMPDIR/index.ts" before status=0
  printf '%s\n' 'upstream changed' > "$target"
  before="$(sha256sum "$target")"

  python3 "$REPO_DIR/scripts/patch_pi_mcp_background.py" "$target" 2>"$TEST_TMPDIR/patch-error" || status=$?

  assert_equals 1 "$status"
  assert_contains "$(<"$TEST_TMPDIR/patch-error")" 'Pi MCP background patch source drift'
  assert_equals "$before" "$(sha256sum "$target")"
}
