#!/usr/bin/env bash
# Shared Pi fast-mode toggle tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

extension_dir="$REPO_DIR/config/shared/ai/pi/fast-mode"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_fast_mode_rewrites_only_supported_openai_codex_requests() {
  assert_file_exists "$extension_dir/core.ts"
  [ -f "$extension_dir/core.ts" ] || return

  CORE="file://$extension_dir/core.ts" assert_exit_code 0 node --input-type=module - <<'JS'
const { isFastModeModel, rewriteFastModeProviderRequest } = await import(process.env.CORE);
const check = (condition, message) => { if (!condition) throw new Error(message); };
const payload = { model: "gpt-5.6-sol", stream: true };
check(isFastModeModel({ provider: "openai-codex", id: "gpt-5.6-sol" }), "Sol rejected");
check(isFastModeModel({ provider: "openai-codex", id: "gpt-5.6-luna" }), "Luna rejected");
check(!isFastModeModel({ provider: "openai-codex", id: "gpt-5.6-terra" }), "Terra accepted");
check(!isFastModeModel({ provider: "openai", id: "gpt-5.6-sol" }), "wrong provider accepted");
const rewritten = rewriteFastModeProviderRequest(payload, true, { provider: "openai-codex", id: "gpt-5.6-sol" });
check(rewritten !== payload && rewritten.service_tier === "priority", "supported request not rewritten");
check(rewriteFastModeProviderRequest(payload, false, { provider: "openai-codex", id: "gpt-5.6-sol" }) === payload, "disabled request changed");
check(rewriteFastModeProviderRequest(payload, true, { provider: "openai-codex", id: "gpt-5.6-terra" }) === payload, "unsupported request changed");
JS
}

test_fast_mode_extension_toggles_and_persists_session_state() {
  assert_file_exists "$extension_dir/index.ts"
  [ -f "$extension_dir/index.ts" ] || return

  local output="$TEST_TMPDIR/rpc.jsonl"
  printf '%s\n' \
    '{"id":"commands","type":"get_commands"}' \
    '{"id":"on","type":"prompt","message":"/fast on"}' \
    '{"id":"status","type":"prompt","message":"/fast status"}' |
    pi --mode rpc --no-session --no-extensions -e "$extension_dir/index.ts" >"$output"

  assert_exit_code 0 jq -e '
    select(.type == "response" and .id == "commands" and .success == true) |
    any(.data.commands[]; .name == "fast")
  ' "$output"
  assert_exit_code 0 jq -e 'select(.type == "entry_appended" and .entry.customType == "fast-mode-state" and .entry.data.enabled == true)' "$output"
  assert_exit_code 0 jq -e 'select(.type == "extension_ui_request" and .method == "notify" and (.message | contains("Fast mode is on")))' "$output"
}
