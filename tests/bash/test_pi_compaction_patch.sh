#!/usr/bin/env bash
# Pi auto-compaction steering patch tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

write_unpatched_fixture() {
  cat > "$1" <<'EOF'
                if (extensionResult?.cancel) {
                    this._emit({
                        type: "compaction_end",
                        reason,
                        result: undefined,
                        aborted: true,
                        willRetry: false,
                    });
                }
            if (this._autoCompactionAbortController.signal.aborted) {
                this._emit({
                    type: "compaction_end",
                    reason,
                    result: undefined,
                    aborted: true,
                    willRetry: false,
                });
            }
            this._emit({ type: "compaction_end", reason, result, aborted: false, willRetry });
        catch (error) {
            if (started) {
                this._emit({
                    type: "compaction_end",
                    reason,
                    result: undefined,
                    aborted: false,
                    willRetry: false,
                    errorMessage: reason === "overflow"
                        ? `Context overflow recovery failed: ${errorMessage}`
                        : `Auto-compaction failed: ${errorMessage}`,
                });
            }
        }
EOF
}

test_pi_package_patches_after_npm_dependency_fetch() {
  local package post_patch pre_install
  package="$(<"$REPO_DIR/packages/pi-agent.nix")"
  post_patch="${package#*postPatch = \'\'}"
  post_patch="${post_patch%%  preInstall =*}"
  pre_install="${package#*preInstall = \'\'}"

  assert_contains "$package" "preInstall = ''"
  assert_not_contains "$post_patch" 'patch_pi_compaction.py'
  assert_contains "$pre_install" "python3 \${../scripts/patch_pi_compaction.py} dist/core/agent-session.js"
}

test_pi_compaction_patch_is_idempotent() {
  local target="$TEST_TMPDIR/agent-session.js" before
  write_unpatched_fixture "$target"

  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE"
  assert_equals 4 "$(grep -c 'this._autoCompactionAbortController = undefined;' "$target")"

  before="$(sha256sum "$target")"
  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE"
  assert_equals "$before" "$(sha256sum "$target")"
}

test_pi_compaction_patch_rejects_source_drift() {
  local target="$TEST_TMPDIR/agent-session.js" before status=0
  printf '%s\n' 'upstream changed' > "$target"
  before="$(sha256sum "$target")"

  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>"$TEST_TMPDIR/patch-error" || status=$?

  assert_equals 1 "$status"
  assert_contains "$(<"$TEST_TMPDIR/patch-error")" 'Pi compaction patch source drift'
  assert_equals "$before" "$(sha256sum "$target")"
}
