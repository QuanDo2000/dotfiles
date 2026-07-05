#!/usr/bin/env bash

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

test_all_runs_obsidian_on_arch_with_prereqs() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  local bindir="$TEST_HOME/bin"
  mkdir -p "$bindir"
  printf 'ID=arch\n' > "$osrel"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/npm"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/ob"
  printf '#!/usr/bin/env bash\n[[ "$*" == "--user show-environment" ]] && exit 0\nexit 0\n' > "$bindir/systemctl"
  chmod +x "$bindir/npm" "$bindir/ob" "$bindir/systemctl"

  local output
  output=$(OS_RELEASE="$osrel" PATH="$bindir:$PATH" bash "$DOTFILE_CMD" --dry all 2>&1)
  assert_contains "$output" "Setting up Obsidian headless sync"

  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_update_command_in_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "update"
  assert_contains "$output" "Update system packages"
}

test_dry_run_update_command() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry update
}

test_languages_command_in_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "languages"
}

test_dry_run_languages_command() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages
}

test_dry_run_languages_zig() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages zig
}

test_dry_run_languages_odin() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages odin
}

test_dry_run_languages_gleam() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages gleam
}

test_dry_run_languages_jank() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages jank
}

test_packages_nixos_dry() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "Updating packages"

  # Don't leak the uname mock into later tests in this file.
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_help_has_no_direct_zsh_or_tmux_commands() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  if [[ "$output" == *$'\n  zsh '* || "$output" == *$'\n  tmux '* || "$output" == *$'\n  ai '* ]]; then
    echo "  FAILED: help text should not expose direct zsh/tmux/ai commands" >> "$ERROR_FILE"
  fi
}

test_direct_zsh_tmux_and_ai_commands_fail() {
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry zsh
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry tmux
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry ai
}
