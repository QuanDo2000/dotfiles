#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_HOME"
}

test_help_exits_zero() {
  local output
  output=$(bash "$DOTFILE_CMD" -h 2>&1)
  assert_exit_code 0 bash "$DOTFILE_CMD" -h
  assert_contains "$output" "Usage"
  assert_contains "$output" "Commands"
  assert_contains "$output" "Options"
}

test_flag_dry() {
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -h
}

test_flag_force() {
  assert_exit_code 0 bash "$DOTFILE_CMD" -f -h
}

test_flag_quiet() {
  local output
  output=$(bash "$DOTFILE_CMD" -q -h 2>&1)
  assert_contains "$output" "Usage"
}

test_combined_flags() {
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -f -q -h
}

test_unknown_command_fails() {
  assert_exit_code 1 bash "$DOTFILE_CMD" nonsense_command
}

test_long_flag_dry() {
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry --help
}

test_long_flag_force() {
  assert_exit_code 0 bash "$DOTFILE_CMD" --force --help
}

test_long_flag_quiet() {
  assert_exit_code 0 bash "$DOTFILE_CMD" --quiet --help
}

test_long_flag_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "Usage"
}

test_verify_command_runs() {
  assert_exit_code 0 bash "$DOTFILE_CMD" verify
}

test_dry_run_default_command() {
  # Unix installer does not target Windows (Windows has its own PowerShell setup).
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry all
}
