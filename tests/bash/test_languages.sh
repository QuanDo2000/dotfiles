#!/bin/bash
# Tests for scripts/languages.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh languages.sh
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

# Helper: install a fake executable in FAKE_BIN that runs $body.
mock_cmd() {
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
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
  # Shadow `command` so `command -v minisign` reports "not found", even on
  # hosts where minisign is genuinely installed. Keeps PATH intact so basic
  # tools like rm and the package-manager binaries are still usable.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "minisign" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_debian_logs_install() {
  DRY=true
  detect_platform() { echo "debian"; }
  export -f detect_platform
  # Shadow `command` so `command -v minisign` reports "not found", even on
  # hosts where minisign is genuinely installed. Keeps PATH intact so basic
  # tools like rm and the package-manager binaries are still usable.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "minisign" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_mac_logs_install() {
  DRY=true
  detect_platform() { echo "mac"; }
  export -f detect_platform
  # Shadow `command` so `command -v minisign` reports "not found", even on
  # hosts where minisign is genuinely installed. Keeps PATH intact so basic
  # tools like rm and the package-manager binaries are still usable.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "minisign" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

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
  # Pretend latest is 0.14.1 AND that 0.14.1 is already installed.
  # Stubbing http_get_retry feeds zig_latest_stable a synthetic index.json
  # so the test runs offline and stays deterministic.
  mkdir -p "$HOME/.local/zig-0.14.1"
  touch "$HOME/.local/zig-0.14.1/zig"
  ln -s "$HOME/.local/zig-0.14.1/zig" "$HOME/.local/bin/zig"

  http_get_retry() { echo '{"0.14.1": {}}'; }
  export -f http_get_retry
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

# ---------------------------------------------------------------------------
# install_languages
# ---------------------------------------------------------------------------

test_install_languages_dry_run() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Installing Jank"
}

test_install_languages_zig_only_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages zig 2>&1)
  assert_contains "$output" "Installing Zig"
}

test_install_languages_all_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages all 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Installing Jank"
}

test_install_languages_jank_only_arg() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(install_languages jank 2>&1)
  assert_contains "$output" "Installing Jank"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages jank should not run Zig" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Odin"* ]]; then
    echo "  FAILED: install_languages jank should not run Odin" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Gleam"* ]]; then
    echo "  FAILED: install_languages jank should not run Gleam" >> "$ERROR_FILE"
  fi
}

test_install_languages_unknown_fails() {
  local exit_code=0
  ( install_languages java ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: install_languages should fail on unknown language" >> "$ERROR_FILE"
  fi
}

test_install_languages_gleam_only_arg() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages gleam should not run Zig" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Odin"* ]]; then
    echo "  FAILED: install_languages gleam should not run Odin" >> "$ERROR_FILE"
  fi
}

test_install_languages_odin_only_arg() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages odin 2>&1)
  assert_contains "$output" "Installing Odin"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages odin should not run Zig" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# update_languages
# ---------------------------------------------------------------------------

test_update_languages_dry_run_no_install() {
  DRY=true
  # update_zig/odin/gleam check ~/.local/bin/<lang> in the temp HOME (none
  # exist → silent no-op). update_jank uses `command -v jank` which finds
  # the system PATH — shadow it so the test stays independent of the host.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(update_languages 2>&1)
  assert_equals "" "$output"
}

# ---------------------------------------------------------------------------
# odin_target_triple
# ---------------------------------------------------------------------------

test_odin_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(odin_target_triple)"
  assert_equals "linux-amd64" "$result"
}

test_odin_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(odin_target_triple)"
  assert_equals "linux-arm64" "$result"
}

test_odin_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(odin_target_triple)"
  assert_equals "macos-amd64" "$result"
}

test_odin_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(odin_target_triple)"
  assert_equals "macos-arm64" "$result"
}

test_odin_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( odin_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: odin_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# odin_latest_release
# ---------------------------------------------------------------------------

test_odin_latest_release_uses_passed_json() {
  # If a JSON arg is given, return it verbatim — http_get_retry must NOT be called.
  http_get_retry() {
    echo "  FAILED: http_get_retry should not be called when JSON arg supplied" >> "$ERROR_FILE"
    return 1
  }
  export -f http_get_retry

  local result
  result="$(odin_latest_release '{"tag_name": "dev-2026-04"}')"
  assert_equals '{"tag_name": "dev-2026-04"}' "$result"
}

test_odin_latest_release_fetches_when_no_arg() {
  http_get_retry() { echo '{"tag_name": "dev-2026-04"}'; }
  export -f http_get_retry

  local result
  result="$(odin_latest_release)"
  assert_equals '{"tag_name": "dev-2026-04"}' "$result"
}

# ---------------------------------------------------------------------------
# odin_current_installed_version
# ---------------------------------------------------------------------------

test_odin_current_installed_version_none() {
  local result
  result="$(odin_current_installed_version)"
  assert_equals "" "$result"
}

test_odin_current_installed_version_ours_returns_tag() {
  mkdir -p "$HOME/.local/odin-dev-2026-04"
  touch "$HOME/.local/odin-dev-2026-04/odin"
  ln -s "$HOME/.local/odin-dev-2026-04/odin" "$HOME/.local/bin/odin"

  local result
  result="$(odin_current_installed_version)"
  assert_equals "dev-2026-04" "$result"
}

test_odin_current_installed_version_foreign_returns_empty() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/odin"
  ln -s "$HOME/elsewhere/odin" "$HOME/.local/bin/odin"

  local result
  result="$(odin_current_installed_version)"
  assert_equals "" "$result"
}

# ---------------------------------------------------------------------------
# install_odin
# ---------------------------------------------------------------------------

test_install_odin_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Finished"
  if [[ -e "$HOME/.local/odin-dev-2026-04" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_odin_already_installed_short_circuits() {
  # Pretend latest is dev-2026-04 AND that it's already installed.
  mkdir -p "$HOME/.local/odin-dev-2026-04"
  touch "$HOME/.local/odin-dev-2026-04/odin"
  ln -s "$HOME/.local/odin-dev-2026-04/odin" "$HOME/.local/bin/odin"

  http_get_retry() { echo '{"tag_name": "dev-2026-04", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
  assert_contains "$output" "Already installed Odin dev-2026-04"
}

# ---------------------------------------------------------------------------
# update_odin
# ---------------------------------------------------------------------------

test_update_odin_no_op_when_not_installed() {
  local output
  output=$(update_odin 2>&1)
  assert_equals "" "$output"
}

test_update_odin_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/odin"
  ln -s "$HOME/elsewhere/odin" "$HOME/.local/bin/odin"

  local output
  output=$(update_odin 2>&1)
  assert_equals "" "$output"
}

test_update_odin_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/odin-dev-2026-03"
  touch "$HOME/.local/odin-dev-2026-03/odin"
  ln -s "$HOME/.local/odin-dev-2026-03/odin" "$HOME/.local/bin/odin"

  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(update_odin 2>&1)
  assert_contains "$output" "Installing Odin"
}

# ---------------------------------------------------------------------------
# gleam_target_triple
# ---------------------------------------------------------------------------

test_gleam_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(gleam_target_triple)"
  assert_equals "x86_64-unknown-linux-musl" "$result"
}

test_gleam_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(gleam_target_triple)"
  assert_equals "aarch64-unknown-linux-musl" "$result"
}

test_gleam_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(gleam_target_triple)"
  assert_equals "x86_64-apple-darwin" "$result"
}

test_gleam_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(gleam_target_triple)"
  assert_equals "aarch64-apple-darwin" "$result"
}

test_gleam_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( gleam_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: gleam_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# gleam_latest_release
# ---------------------------------------------------------------------------

test_gleam_latest_release_uses_passed_json() {
  http_get_retry() {
    echo "  FAILED: http_get_retry should not be called when JSON arg supplied" >> "$ERROR_FILE"
    return 1
  }
  export -f http_get_retry

  local result
  result="$(gleam_latest_release '{"tag_name": "v1.15.4"}')"
  assert_equals '{"tag_name": "v1.15.4"}' "$result"
}

test_gleam_latest_release_fetches_when_no_arg() {
  http_get_retry() { echo '{"tag_name": "v1.15.4"}'; }
  export -f http_get_retry

  local result
  result="$(gleam_latest_release)"
  assert_equals '{"tag_name": "v1.15.4"}' "$result"
}

# ---------------------------------------------------------------------------
# gleam_current_installed_version
# ---------------------------------------------------------------------------

test_gleam_current_installed_version_none() {
  local result
  result="$(gleam_current_installed_version)"
  assert_equals "" "$result"
}

test_gleam_current_installed_version_ours_returns_tag() {
  mkdir -p "$HOME/.local/gleam-v1.15.4"
  touch "$HOME/.local/gleam-v1.15.4/gleam"
  ln -s "$HOME/.local/gleam-v1.15.4/gleam" "$HOME/.local/bin/gleam"

  local result
  result="$(gleam_current_installed_version)"
  assert_equals "v1.15.4" "$result"
}

test_gleam_current_installed_version_foreign_returns_empty() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/gleam"
  ln -s "$HOME/elsewhere/gleam" "$HOME/.local/bin/gleam"

  local result
  result="$(gleam_current_installed_version)"
  assert_equals "" "$result"
}

# ---------------------------------------------------------------------------
# ensure_erlang
# ---------------------------------------------------------------------------

test_ensure_erlang_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/erl"
  chmod +x "$HOME/.local/bin/erl"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_erlang 2>&1)
  if [[ "$output" == *"Erlang/OTP not found"* ]]; then
    echo "  FAILED: ensure_erlang should noop when erl already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_erlang_dry_run_arch_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}

test_ensure_erlang_dry_run_debian_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}

test_ensure_erlang_dry_run_mac_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}

# ---------------------------------------------------------------------------
# ensure_rebar3
# ---------------------------------------------------------------------------

test_ensure_rebar3_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/rebar3"
  chmod +x "$HOME/.local/bin/rebar3"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_rebar3 2>&1)
  if [[ "$output" == *"rebar3 not found"* ]]; then
    echo "  FAILED: ensure_rebar3 should noop when already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_rebar3_dry_run_arch_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}

test_ensure_rebar3_dry_run_debian_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}

test_ensure_rebar3_dry_run_mac_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}

# ---------------------------------------------------------------------------
# install_gleam
# ---------------------------------------------------------------------------

test_install_gleam_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Finished"
  if [[ -e "$HOME/.local/gleam-v1.15.4" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_gleam_already_installed_short_circuits() {
  mkdir -p "$HOME/.local/gleam-v1.15.4"
  touch "$HOME/.local/gleam-v1.15.4/gleam"
  ln -s "$HOME/.local/gleam-v1.15.4/gleam" "$HOME/.local/bin/gleam"

  http_get_retry() { echo '{"tag_name": "v1.15.4", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_gleam 2>&1)
  assert_contains "$output" "Already installed Gleam v1.15.4"
}

# ---------------------------------------------------------------------------
# update_gleam
# ---------------------------------------------------------------------------

test_update_gleam_no_op_when_not_installed() {
  local output
  output=$(update_gleam 2>&1)
  assert_equals "" "$output"
}

test_update_gleam_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/gleam"
  ln -s "$HOME/elsewhere/gleam" "$HOME/.local/bin/gleam"

  local output
  output=$(update_gleam 2>&1)
  assert_equals "" "$output"
}

test_update_gleam_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/gleam-v1.14.0"
  touch "$HOME/.local/gleam-v1.14.0/gleam"
  ln -s "$HOME/.local/gleam-v1.14.0/gleam" "$HOME/.local/bin/gleam"

  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(update_gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
}

# ---------------------------------------------------------------------------
# jank_check_platform
# ---------------------------------------------------------------------------

test_jank_check_platform_mac_arm64_succeeds() {
  mock_uname Darwin
  mock_uname_m arm64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  jank_check_platform
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_mac_x86_64_returns_nonzero() {
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local rc=0
  jank_check_platform || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on Intel mac" >> "$ERROR_FILE"
  fi
}

test_jank_check_platform_arch_succeeds() {
  detect_platform() { echo "arch"; }
  export -f detect_platform

  jank_check_platform
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_ubuntu_via_arg_succeeds() {
  detect_platform() { echo "debian"; }
  export -f detect_platform

  jank_check_platform ubuntu
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_debian_via_arg_returns_nonzero() {
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local rc=0
  jank_check_platform debian || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on plain Debian" >> "$ERROR_FILE"
  fi
}

test_jank_check_platform_unknown_returns_nonzero() {
  detect_platform() { echo "unknown"; }
  export -f detect_platform

  local rc=0
  jank_check_platform || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on unknown platform" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# jank_current_installed_version
# ---------------------------------------------------------------------------

test_jank_current_installed_version_none() {
  # Shadow command so `command -v jank` reports not found regardless of host.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local result
  result="$(jank_current_installed_version)"
  assert_equals "" "$result"
}

test_jank_current_installed_version_present() {
  # Drop a fake jank on PATH.
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local result
  result="$(jank_current_installed_version)"
  assert_equals "installed" "$result"
}

# ---------------------------------------------------------------------------
# install_jank
# ---------------------------------------------------------------------------

test_install_jank_unsupported_platform_skips() {
  # Mocked Intel mac: jank_check_platform returns non-zero.
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output rc=0
  output=$(install_jank 2>&1) || rc=$?
  assert_equals "0" "$rc"
  assert_contains "$output" "Skipping Jank"
}

test_install_jank_dry_run_arch() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform
  # Shadow command so the test stays correct even if jank is on the host PATH
  # and a future refactor moves the skip-if-installed gate before the dry-run gate.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(install_jank 2>&1)
  assert_contains "$output" "Installing Jank"
  assert_contains "$output" "Would install Jank"
  assert_contains "$output" "Finished installing Jank (dry run)"
}

test_install_jank_already_installed_short_circuits() {
  detect_platform() { echo "arch"; }
  export -f detect_platform
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(install_jank 2>&1)
  assert_contains "$output" "Already installed Jank"
}

# ---------------------------------------------------------------------------
# update_jank
# ---------------------------------------------------------------------------

test_update_jank_no_op_when_not_installed() {
  detect_platform() { echo "arch"; }
  export -f detect_platform
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(update_jank 2>&1)
  assert_equals "" "$output"
}

test_update_jank_unsupported_platform_no_op() {
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output rc=0
  output=$(update_jank 2>&1) || rc=$?
  assert_equals "0" "$rc"
  assert_equals "" "$output"
}

test_update_jank_dry_run_when_installed() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(update_jank 2>&1)
  assert_contains "$output" "Updating Jank"
  assert_contains "$output" "Would update Jank"
  assert_contains "$output" "Finished updating Jank (dry run)"
}

# ---------------------------------------------------------------------------
# _assert_single_top_dir
# ---------------------------------------------------------------------------

test_assert_single_top_dir_returns_path_when_one_dir() {
  local extract_dir="$TEST_TMPDIR/single"
  mkdir -p "$extract_dir/inner"

  local result
  result=$(_assert_single_top_dir "$extract_dir" "TestPkg")
  assert_equals "$extract_dir/inner" "$result"
}

test_assert_single_top_dir_fails_when_zero_dirs() {
  local extract_dir="$TEST_TMPDIR/zero"
  mkdir -p "$extract_dir"
  # No subdirs.

  local output exit_code=0
  output=$(_assert_single_top_dir "$extract_dir" "TestPkg" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _assert_single_top_dir should fail with 0 dirs" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "TestPkg"
  assert_contains "$output" "0 top-level dirs"
}

test_assert_single_top_dir_fails_when_multiple_dirs() {
  local extract_dir="$TEST_TMPDIR/multi"
  mkdir -p "$extract_dir/a" "$extract_dir/b"

  local output exit_code=0
  output=$(_assert_single_top_dir "$extract_dir" "TestPkg" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _assert_single_top_dir should fail with 2 dirs" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "2 top-level dirs"
}

# ---------------------------------------------------------------------------
# _install_into_local
# ---------------------------------------------------------------------------

test_install_into_local_creates_target_and_symlink() {
  local extracted="$TEST_TMPDIR/extracted"
  mkdir -p "$extracted"
  echo "fake binary" > "$extracted/foo"
  chmod +x "$extracted/foo"

  _install_into_local "foo" "v1.0" "foo" "$extracted"

  assert_file_exists "$HOME/.local/foo-v1.0/foo"
  assert_symlink "$HOME/.local/bin/foo" "$HOME/.local/foo-v1.0/foo"
}

test_install_into_local_cleans_old_versions() {
  # Pre-create a prior version that should be removed by the cleanup loop.
  mkdir -p "$HOME/.local/foo-v0.9"
  echo "old" > "$HOME/.local/foo-v0.9/foo"

  local extracted="$TEST_TMPDIR/extracted"
  mkdir -p "$extracted"
  echo "new" > "$extracted/foo"

  _install_into_local "foo" "v1.0" "foo" "$extracted"

  assert_file_exists "$HOME/.local/foo-v1.0/foo"
  if [ -d "$HOME/.local/foo-v0.9" ]; then
    echo "  FAILED: _install_into_local should have removed old version foo-v0.9" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# _strip_sha256_prefix
# ---------------------------------------------------------------------------

test_strip_sha256_prefix_strips_known_format() {
  local result
  result=$(_strip_sha256_prefix "sha256:deadbeef")
  assert_equals "deadbeef" "$result"
}

test_strip_sha256_prefix_fails_on_bare_hex() {
  local output exit_code=0
  output=$(_strip_sha256_prefix "deadbeef" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _strip_sha256_prefix should fail on bare hex" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Unexpected digest format"
}

test_strip_sha256_prefix_fails_on_sha512_prefix() {
  local output exit_code=0
  output=$(_strip_sha256_prefix "sha512:abc" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _strip_sha256_prefix should fail on sha512: prefix" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Unexpected digest format"
}
