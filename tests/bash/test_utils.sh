#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source_scripts utils.sh
}

test_info_output() {
  local output
  output=$(info "hello world")
  assert_contains "$output" "hello world"
}

test_success_output() {
  local output
  output=$(success "it worked")
  assert_contains "$output" "it worked"
}

test_user_output() {
  local output
  output=$(user "pick one")
  assert_contains "$output" "pick one"
}

test_fail_exits() {
  assert_exit_code 1 bash -c "source '$REPO_DIR/scripts/utils.sh'; fail 'boom'"
}

test_fail_soft_no_exit() {
  local output
  output=$(fail_soft "warning")
  assert_contains "$output" "warning"
}

test_quiet_suppresses_info() {
  QUIET=true
  local output
  output=$(info "should not appear")
  assert_equals "" "$output"
}

test_quiet_suppresses_success() {
  QUIET=true
  local output
  output=$(success "should not appear")
  assert_equals "" "$output"
}

test_quiet_force_flag() {
  QUIET=true
  local output
  output=$(info "forced message" --force)
  assert_contains "$output" "forced message"
}

test_quiet_does_not_suppress_user() {
  QUIET=true
  local output
  output=$(user "msg")
  assert_contains "$output" "msg"
}

test_success_force_flag() {
  QUIET=true
  local output
  output=$(success "forced" --force)
  assert_contains "$output" "forced"
}

test_fail_output_contains_message() {
  local output
  output=$(fail "specific error" 2>&1 || true)
  assert_contains "$output" "specific error"
}

test_default_globals() {
  unset DRY QUIET FORCE
  source "$REPO_DIR/scripts/utils.sh"
  assert_equals "false" "$DRY"
  assert_equals "false" "$QUIET"
  assert_equals "false" "$FORCE"
}

test_mock_uname_m_overrides_uname_m() {
  init_test_env
  mock_uname_m aarch64
  local result
  result="$(uname -m)"
  assert_equals "aarch64" "$result"
  cleanup_test_env
}

test_cleanup_resets_uname_m() {
  init_test_env
  mock_uname_m aarch64
  cleanup_test_env
  init_test_env
  local result
  result="$(uname -m)"
  # After cleanup + fresh init, uname -m should be the real value (NOT "aarch64")
  if [[ "$result" == "aarch64" ]] && [[ "$(command uname -m)" != "aarch64" ]]; then
    echo "  FAILED: uname -m mock leaked across tests" >> "$ERROR_FILE"
  fi
  cleanup_test_env
}
