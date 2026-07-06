#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh languages.sh
}

teardown() {
  cleanup_test_env
}

test_install_languages_all_skips_to_home_manager() {
  DRY=true
  local platform output
  for platform in arch debian mac nixos; do
    MOCK_PLATFORM="$platform"
    detect_platform() { echo "$MOCK_PLATFORM"; }
    export MOCK_PLATFORM
    export -f detect_platform

    output=$(install_languages all 2>&1)
    assert_contains "$output" "Zig is managed by Home Manager on $platform"
    assert_contains "$output" "Odin is managed by Home Manager on $platform"
    assert_contains "$output" "Gleam is managed by Home Manager on $platform"
    assert_contains "$output" "Jank is managed by Home Manager on $platform"
    assert_not_contains "$output" "Installing"
  done
}

test_install_languages_single_target_skips_to_home_manager() {
  DRY=true
  detect_platform() { echo "nixos"; }
  export -f detect_platform

  local output
  output=$(install_languages gleam 2>&1)
  assert_contains "$output" "Gleam is managed by Home Manager on nixos"
  assert_not_contains "$output" "Zig is managed"
  assert_not_contains "$output" "Odin is managed"
  assert_not_contains "$output" "Jank is managed"
}

test_update_languages_skips_to_home_manager() {
  DRY=true
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(update_languages 2>&1)
  assert_contains "$output" "Zig is managed by Home Manager on debian"
  assert_contains "$output" "Jank is managed by Home Manager on debian"
  assert_not_contains "$output" "Updating"
}

test_install_languages_unknown_fails() {
  local output rc=0
  output=$(install_languages nonsense 2>&1) || rc=$?
  assert_equals "1" "$rc"
  assert_contains "$output" "Unknown language: nonsense"
}
