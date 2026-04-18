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
# _sha256 (portable hash)
# ---------------------------------------------------------------------------

test_sha256_matches_known_value() {
  # echo -n "hello" | sha256sum -> 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
  echo -n "hello" > "$TEST_TMPDIR/hello.txt"
  local result
  result="$(_sha256 "$TEST_TMPDIR/hello.txt")"
  assert_equals "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" "$result"
}

# ---------------------------------------------------------------------------
# _shuffle_lines (portable awk shuffle)
# ---------------------------------------------------------------------------

test_shuffle_lines_preserves_input_set() {
  local input sorted_in sorted_out
  input=$'a\nb\nc\nd\ne'
  sorted_in="$(echo "$input" | sort)"
  sorted_out="$(echo "$input" | _shuffle_lines | sort)"
  assert_equals "$sorted_in" "$sorted_out"
}

test_shuffle_lines_empty_input() {
  local result
  result="$(echo -n "" | _shuffle_lines)"
  assert_equals "" "$result"
}

test_shuffle_lines_single_line() {
  local result
  result="$(echo "only" | _shuffle_lines)"
  assert_equals "only" "$result"
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

# ---------------------------------------------------------------------------
# zig_latest_stable
# ---------------------------------------------------------------------------

test_zig_latest_stable_picks_highest() {
  http_get_retry() { cat <<'JSON'
{"master": {"version": "0.15.0-dev"}, "0.13.0": {}, "0.14.1": {}, "0.12.0": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.14.1" "$result"
}

test_zig_latest_stable_skips_master() {
  http_get_retry() { cat <<'JSON'
{"master": {}, "0.10.0": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.10.0" "$result"
}

test_zig_latest_stable_skips_rc_versions() {
  http_get_retry() { cat <<'JSON'
{"master": {}, "0.14.1": {}, "0.15.0-rc1": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.14.1" "$result"
}

test_zig_latest_stable_fails_on_empty() {
  http_get_retry() { echo '{}'; }
  export -f http_get_retry

  local exit_code=0
  ( zig_latest_stable ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: zig_latest_stable should fail on empty index" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# zig_current_installed_version
# ---------------------------------------------------------------------------

test_zig_current_installed_version_none() {
  local result
  result="$(zig_current_installed_version)"
  assert_equals "" "$result"
}

test_zig_current_installed_version_ours_returns_version() {
  mkdir -p "$HOME/.local/zig-0.14.1"
  touch "$HOME/.local/zig-0.14.1/zig"
  ln -s "$HOME/.local/zig-0.14.1/zig" "$HOME/.local/bin/zig"

  local result
  result="$(zig_current_installed_version)"
  assert_equals "0.14.1" "$result"
}

test_zig_current_installed_version_foreign_returns_empty() {
  # Symlink points outside ~/.local/zig-*/
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/zig"
  ln -s "$HOME/elsewhere/zig" "$HOME/.local/bin/zig"

  local result
  result="$(zig_current_installed_version)"
  assert_equals "" "$result"
}

# ---------------------------------------------------------------------------
# ensure_minisign
# ---------------------------------------------------------------------------

test_ensure_minisign_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/minisign"
  chmod +x "$HOME/.local/bin/minisign"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_minisign 2>&1)
  # No "Installing minisign" line should appear
  if [[ "$output" == *"Installing minisign"* ]]; then
    echo "  FAILED: ensure_minisign should noop when minisign already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_minisign_dry_run_arch_logs_install() {
  DRY=true
  mock_uname Linux
  # Stub /etc/os-release detection — easier to override detect_platform directly
  detect_platform() { echo "arch"; }
  export -f detect_platform
  # Make sure minisign is NOT on PATH
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_debian_logs_install() {
  DRY=true
  detect_platform() { echo "debian"; }
  export -f detect_platform
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_mac_logs_install() {
  DRY=true
  detect_platform() { echo "mac"; }
  export -f detect_platform
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

# ---------------------------------------------------------------------------
# install_zig
# ---------------------------------------------------------------------------

test_install_zig_dry_run() {
  DRY=true
  # Stub the lookup so we don't hit network. Pretend there is no install yet.
  zig_latest_stable() { echo "0.14.1"; }
  export -f zig_latest_stable
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_zig 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Finished"
  # No tarball should land on disk
  if [[ -e "$HOME/.local/zig-0.14.1" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_zig_already_installed_short_circuits() {
  # Pretend latest is 0.14.1 AND that 0.14.1 is already installed
  mkdir -p "$HOME/.local/zig-0.14.1"
  touch "$HOME/.local/zig-0.14.1/zig"
  ln -s "$HOME/.local/zig-0.14.1/zig" "$HOME/.local/bin/zig"

  zig_latest_stable() { echo "0.14.1"; }
  export -f zig_latest_stable
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_zig 2>&1)
  assert_contains "$output" "Already installed Zig 0.14.1"
}

# ---------------------------------------------------------------------------
# update_zig
# ---------------------------------------------------------------------------

test_update_zig_no_op_when_not_installed() {
  # No ~/.local/bin/zig at all
  local output
  output=$(update_zig 2>&1)
  assert_equals "" "$output"
}

test_update_zig_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/zig"
  ln -s "$HOME/elsewhere/zig" "$HOME/.local/bin/zig"

  local output
  output=$(update_zig 2>&1)
  assert_equals "" "$output"
}

test_update_zig_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/zig-0.14.0"
  touch "$HOME/.local/zig-0.14.0/zig"
  ln -s "$HOME/.local/zig-0.14.0/zig" "$HOME/.local/bin/zig"

  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(update_zig 2>&1)
  assert_contains "$output" "Installing Zig"
}
