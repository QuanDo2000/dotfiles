#!/usr/bin/env bash
# Pi auto-compaction steering patch tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

write_unpatched_compaction_fixture() {
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

write_unpatched_fixture() {
  write_unpatched_compaction_fixture "$1"
  cat >> "$1" <<'EOF'
                if (inputResult.action === "transform") {
                    currentText = inputResult.text;
                    currentImages = inputResult.images ?? currentImages;
                }
            }
            // Expand skill commands (/skill:name args) and prompt templates (/template args)
EOF
}

test_pi_package_patches_after_npm_dependency_fetch() {
  local package post_patch pre_install
  package="$(<"$REPO_DIR/packages/pi-agent.nix")"
  post_patch="${package#*postPatch = \'\'}"
  post_patch="${post_patch%%  preInstall =*}"
  pre_install="${package#*preInstall = \'\'}"

  assert_contains "$package" "preInstall = ''"
  assert_not_contains "$package" 'lib.getExe jq'
  assert_contains "$post_patch" 'delete packageJson.devDependencies'
  assert_not_contains "$post_patch" 'patch_pi_compaction.py'
  assert_contains "$pre_install" "python3 \${../scripts/patch_pi_compaction.py} dist/core/agent-session.js"
}

test_pi_compaction_patch_delivers_late_steering_after_input_hook() {
  local target="$TEST_TMPDIR/agent-session.js" output
  write_unpatched_compaction_fixture "$TEST_TMPDIR/compaction-source"
  {
    printf '/*\n'
    cat "$TEST_TMPDIR/compaction-source"
    printf '*/\n'
    cat <<'EOF'
class Session {
    constructor() {
        this._extensionRunner = {
            hasHandlers: () => true,
            emitInput: async () => ({ action: "continue" }),
        };
        this.agent = { state: { isStreaming: false } };
        this._isAgentRunActive = true;
        this.waited = false;
    }
    get isStreaming() {
        return this._isAgentRunActive;
    }
    async waitForIdle() {
        this.waited = true;
        this._isAgentRunActive = false;
    }
    async prompt(text) {
            let currentText = text;
            let currentImages;
            if (this._extensionRunner.hasHandlers("input")) {
                const inputResult = await this._extensionRunner.emitInput(currentText, currentImages, "interactive", this.isStreaming ? "steer" : undefined);
                if (inputResult.action === "handled") {
                    return;
                }
                if (inputResult.action === "transform") {
                    currentText = inputResult.text;
                    currentImages = inputResult.images ?? currentImages;
                }
            }
            // Expand skill commands (/skill:name args) and prompt templates (/template args)
            return this.isStreaming ? "queued" : "sent";
    }
}
const session = new Session();
console.log(await session.prompt("change direction"), session.waited);
EOF
  } > "$target"

  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE"
  output="$(node "$target")"

  assert_equals "sent true" "$output"
}

test_pi_compaction_patch_upgrades_previous_complete_patch() {
  local target="$TEST_TMPDIR/agent-session.js" before status=0
  write_unpatched_fixture "$target"

  python3 - "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("patch", sys.argv[1])
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
path = patch.Path(sys.argv[2])
source = path.read_text()
for emit in patch.PATCHES:
    indent = emit[: len(emit) - len(emit.lstrip())]
    source = source.replace(emit, f"{indent}{patch.CLEAR}\n{emit}")
path.write_text(source)
PY

  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE" || status=$?

  assert_equals 0 "$status"
  assert_contains "$(<"$target")" 'Input hooks can outlive the core agent run'

  before="$(sha256sum "$target")"
  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE"
  assert_equals "$before" "$(sha256sum "$target")"
}

test_pi_compaction_patch_accepts_formatted_error_message() {
  local target="$TEST_TMPDIR/agent-session.js" status=0
  write_unpatched_fixture "$target"

  python3 - "$target" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
old = '''                    errorMessage: reason === "overflow"
                        ? `Context overflow recovery failed: ${errorMessage}`
                        : `Auto-compaction failed: ${errorMessage}`,'''
new = '''                    errorMessage: formattedErrorMessage,'''
assert source.count(old) == 1
path.write_text(source.replace(old, new))
PY

  python3 "$REPO_DIR/scripts/patch_pi_compaction.py" "$target" 2>>"$ERROR_FILE" || status=$?

  assert_equals 0 "$status"
  assert_equals 4 "$(grep -c 'this._autoCompactionAbortController = undefined;' "$target")"
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
