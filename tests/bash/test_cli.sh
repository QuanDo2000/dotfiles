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
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  mkdir -p "$HOME/.local/bin"
  local f src
  for f in .zshrc .zshrc.base .tmux.conf .vimrc .gitconfig .zprofile; do
    case "$f" in
      .zshrc) src="$REPO_DIR/config/unix/.zshrc.base" ;;
      .gitconfig|.vimrc) src="$REPO_DIR/config/shared/$f" ;;
      *) src="$REPO_DIR/config/unix/$f" ;;
    esac
    ln -s "$src" "$HOME/$f"
  done
  ln -s "$DOTFILE_CMD" "$HOME/.local/bin/dotfile"

  assert_exit_code 0 env OS_RELEASE="$osrel" bash "$DOTFILE_CMD" verify
}

test_dry_run_default_command() {
  # Unix installer does not target Windows (Windows has its own PowerShell setup).
  is_windows_bash && return 0
  local output
  output=$(bash "$DOTFILE_CMD" --dry all 2>&1)
  assert_contains "$output" "Installing packages"
  assert_not_contains "$output" "Updating packages"
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

test_all_skips_removed_noop_commands_on_home_manager_linux() {
  is_windows_bash && return 0
  local distro osrel output
  for distro in arch debian; do
    mock_uname Linux
    osrel="$TEST_HOME/os-release"
    printf 'ID=%s\n' "$distro" > "$osrel"

    output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry all 2>&1)
    assert_not_contains "$output" "Home Manager manages dotfile links"
    assert_not_contains "$output" "Extras are managed by Nix"
    assert_not_contains "$output" "language toolchains are managed by Home Manager"
  done

  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_update_command_in_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "update"
  assert_contains "$output" "Update Nix-managed packages"
}

test_help_describes_verify_as_core_symlink_check() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "Verify core Unix symlinks"
}

test_help_describes_doctor_as_conflict_check() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "doctor"
  assert_contains "$output" "Detect Home Manager file conflicts"
}

test_doctor_command_runs() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" doctor 2>&1)
  assert_contains "$output" "No Home Manager conflicts found"
}

test_help_describes_obsidian_arch_autorun() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "Arch auto-runs during 'all' when ready"
}

test_readme_matches_key_help_text() {
  local readme_text
  readme_text="$(<"$REPO_DIR/README.md")"
  assert_contains "$readme_text" "### Unix Commands"
  assert_contains "$readme_text" "obsidian    Set up Obsidian headless sync (Arch auto-runs during 'all' when ready)"
  assert_contains "$readme_text" "verify      Verify core Unix symlinks"
  assert_contains "$readme_text" "### Windows Commands"
  assert_contains "$readme_text" "dotfile.ps1 [OPTIONS] [COMMAND]"
  assert_contains "$readme_text" "verify      Verify installation"
  assert_contains "$readme_text" 'NixOS flake target is `#${hostName}`'
}

test_agents_describes_windows_core_public_commands() {
  local agents_text
  agents_text="$(<"$REPO_DIR/AGENTS.md")"
  assert_contains "$agents_text" 'same core public commands (`all`, `update`, `packages`, `verify`)'
  assert_not_contains "$agents_text" "Same subcommand structure"
}

test_dry_run_update_command() {
  is_windows_bash && return 0
  local output
  output=$(bash "$DOTFILE_CMD" --dry update 2>&1)
  assert_contains "$output" "Updating packages"
  assert_not_contains "$output" "language toolchains"
}

test_update_runs_doctor_before_package_update() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  printf 'local shell edits\n' > "$HOME/.zshrc"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry update 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" ".zshrc exists but is not Home Manager-owned"
  assert_not_contains "$output" "Updating packages"
}

test_removed_noop_commands_not_in_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_not_contains "$output" $'\n  extras '
  assert_not_contains "$output" $'\n  symlinks '
  assert_not_contains "$output" $'\n  languages '
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

test_help_has_no_removed_commands() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  if [[ "$output" == *$'\n  zsh '* || "$output" == *$'\n  tmux '* || "$output" == *$'\n  ai '* || "$output" == *$'\n  extras '* || "$output" == *$'\n  symlinks '* || "$output" == *$'\n  languages '* ]]; then
    echo "  FAILED: help text should not expose removed commands" >> "$ERROR_FILE"
  fi
}

test_removed_commands_fail() {
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry zsh
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry tmux
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry ai
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry extras
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry symlinks
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry languages
}
