#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
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
