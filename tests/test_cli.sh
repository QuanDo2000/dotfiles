#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILE="$REPO_DIR/shared/bin/dotfile"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  # The dotfile script resolves DOTFILES_DIR from its own location,
  # which is already in the repo — so it will find scripts/ correctly.
  # But ensure_repo checks if DOTFILES_DIR exists (it does), so that's fine.
}

teardown() {
  rm -rf "$TEST_HOME"
}

test_help_exits_zero() {
  local output
  output=$(bash "$DOTFILE" -h 2>&1)
  assert_exit_code 0 bash "$DOTFILE" -h
  assert_contains "$output" "Usage"
  assert_contains "$output" "Commands"
  assert_contains "$output" "Options"
}

test_flag_dry() {
  # -h exits before commands run, so we can combine flags with -h
  assert_exit_code 0 bash "$DOTFILE" -d -h
}

test_flag_force() {
  assert_exit_code 0 bash "$DOTFILE" -f -h
}

test_flag_quiet() {
  local output
  output=$(bash "$DOTFILE" -q -h 2>&1)
  # -h should still print usage even with -q
  assert_contains "$output" "Usage"
}

test_combined_flags() {
  assert_exit_code 0 bash "$DOTFILE" -d -f -q -h
}

test_unknown_command_fails() {
  assert_exit_code 1 bash "$DOTFILE" nonsense_command
}

test_long_flag_dry() {
  assert_exit_code 0 bash "$DOTFILE" --dry --help
}

test_long_flag_force() {
  assert_exit_code 0 bash "$DOTFILE" --force --help
}

test_long_flag_quiet() {
  assert_exit_code 0 bash "$DOTFILE" --quiet --help
}

test_long_flag_help() {
  local output
  output=$(bash "$DOTFILE" --help 2>&1)
  assert_contains "$output" "Usage"
}

test_verify_command_runs() {
  assert_exit_code 0 bash "$DOTFILE" verify
}

test_dry_run_default_command() {
  assert_exit_code 0 bash "$DOTFILE" --dry all
}
