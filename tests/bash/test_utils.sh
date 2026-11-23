#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source_scripts utils.sh
}

test_dry_run_does_not_claim_success() {
  DRY=true
  local output
  output=$(info "Would install packages"; success "Finished installing packages")
  assert_equals "  [DRY ] Would install packages" "$output"
}

test_fail_output_contains_message() {
  local output status=0
  output=$(fail "specific error" 2>&1) || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" "specific error"
}

test_fail_soft_no_exit() {
  local output
  output=$(fail_soft "warning")
  assert_contains "$output" "warning"
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
  local result real_arch
  result="$(uname -m)"
  real_arch="$(command uname -m)"
  assert_equals "$real_arch" "$result"
  cleanup_test_env
}
