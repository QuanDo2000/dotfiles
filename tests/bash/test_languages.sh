#!/bin/bash
# Tests for scripts/languages.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh languages.sh
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# zig_target_triple
# ---------------------------------------------------------------------------

test_zig_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(zig_target_triple)"
  assert_equals "x86_64-linux" "$result"
}

test_zig_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(zig_target_triple)"
  assert_equals "aarch64-linux" "$result"
}

test_zig_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(zig_target_triple)"
  assert_equals "x86_64-macos" "$result"
}

test_zig_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(zig_target_triple)"
  assert_equals "aarch64-macos" "$result"
}

test_zig_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( zig_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: zig_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}
