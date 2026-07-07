#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_HOME"
}

link_core_dotfiles() {
  mkdir -p "$HOME/.local/bin"
  local f src
  for f in .zshrc .zshrc.base .tmux.conf .gitconfig; do
    case "$f" in
      .zshrc) src="$REPO_DIR/config/unix/.zshrc.base" ;;
      .gitconfig) src="$REPO_DIR/config/shared/$f" ;;
      *) src="$REPO_DIR/config/unix/$f" ;;
    esac
    ln -s "$src" "$HOME/$f"
  done
  ln -s "$DOTFILE_CMD" "$HOME/.local/bin/dotfile"
}

assert_checked_flow() {
  local output="$1"
  local pulls_repo="$2"

  assert_equals "2" "$(grep -c "Verifying symlinks" <<<"$output")"
  assert_equals "1" "$(grep -c "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true" <<<"$output")"
  if [[ "$pulls_repo" == "true" ]]; then
    assert_contains "$output" "Updating dotfiles repo"
  else
    assert_not_contains "$output" "Updating dotfiles repo"
  fi
}

test_help_exits_zero() {
  local output
  output=$(bash "$DOTFILE_CMD" -h 2>&1)
  assert_exit_code 0 bash "$DOTFILE_CMD" -h
  assert_contains "$output" "Usage"
  assert_contains "$output" "Commands"
  assert_contains "$output" "Options"
  assert_contains "$output" "update"
  assert_contains "$output" "Update Nix-managed packages"
  assert_contains "$output" "doctor"
  assert_contains "$output" "Detect dotfile and Nix issues"
  assert_contains "$output" "Bootstrap Obsidian Sync login and vault setup"
  assert_not_contains "$output" "obsidian-config"
}

test_doctor_command_runs_with_health_checks() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  assert_exit_code 0 env DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$osrel" bash "$DOTFILE_CMD" doctor
}

test_doctor_fast_skips_nix_eval() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" doctor --fast 2>&1)

  assert_contains "$output" "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true"
  assert_contains "$output" "All checks passed"
}

test_dry_run_default_command() {
  # Unix installer does not target Windows (Windows has its own PowerShell setup).
  is_windows_bash && return 0
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(bash "$DOTFILE_CMD" --dry all 2>&1)
  assert_checked_flow "$output" true
  assert_contains "$output" "Installing packages"
  local repo_line packages_line
  repo_line="$(grep -n "Updating dotfiles repo" <<<"$output" | head -n1 | cut -d: -f1)"
  packages_line="$(grep -n "Installing packages" <<<"$output" | head -n1 | cut -d: -f1)"
  if (( repo_line >= packages_line )); then
    echo "  FAILED: dotfile all should update repo before installing packages" >> "$ERROR_FILE"
  fi
  assert_not_contains "$output" "Updating packages"
}

test_all_does_not_run_obsidian_bootstrap() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  link_core_dotfiles
  with_nix_agent_tools

  printf 'ID=arch\n' > "$osrel"

  local output
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry all 2>&1)
  assert_not_contains "$output" "Setting up Obsidian headless sync"
  assert_contains "$output" "Verifying symlinks"
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_readme_matches_key_help_text() {
  local readme_text
  readme_text="$(<"$REPO_DIR/README.md")"
  assert_contains "$readme_text" "### Unix Commands"
  assert_contains "$readme_text" "obsidian    Bootstrap Obsidian Sync login and vault setup"
  assert_contains "$readme_text" "doctor [--fast]"
  assert_contains "$readme_text" "Detect dotfile and Nix issues"
  assert_contains "$readme_text" "Home Manager owns tracked Obsidian settings"
  assert_contains "$readme_text" "### Windows Commands"
  assert_contains "$readme_text" "dotfile.ps1 [OPTIONS] [COMMAND]"
  assert_contains "$readme_text" "verify      Verify installation"
  assert_contains "$readme_text" 'NixOS flake target is `#${hostName}`'
}

test_agents_describes_windows_core_public_commands() {
  local agents_text
  agents_text="$(<"$REPO_DIR/AGENTS.md")"
  assert_contains "$agents_text" 'Windows keeps its own `verify` command'
  assert_not_contains "$agents_text" "Same subcommand structure"
}

test_dry_run_update_command() {
  is_windows_bash && return 0
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(bash "$DOTFILE_CMD" --dry update 2>&1)
  assert_checked_flow "$output" true
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
  assert_contains "$output" ".zshrc exists but is not a symlink"
  assert_not_contains "$output" "Updating dotfiles repo"
  assert_not_contains "$output" "Updating packages"
}

test_packages_runs_doctor_before_package_install() {
  is_windows_bash && return 0
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  printf 'local shell edits\n' > "$HOME/.zshrc"

  local output exit_code
  set +e
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  exit_code=$?
  set -e

  assert_equals "1" "$exit_code"
  assert_contains "$output" ".zshrc exists but is not a symlink"
  assert_not_contains "$output" "Installing packages"
}

test_packages_nixos_dry() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"
  link_core_dotfiles
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  assert_checked_flow "$output" false
  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "Updating packages"

  # Don't leak the uname mock into later tests in this file.
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}

test_help_has_no_removed_commands() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  if [[ "$output" == *$'\n  zsh '* || "$output" == *$'\n  tmux '* || "$output" == *$'\n  ai '* || "$output" == *$'\n  extras '* || "$output" == *$'\n  symlinks '* || "$output" == *$'\n  languages '* || "$output" == *$'\n  verify '* || "$output" == *$'\n  obsidian-config'* ]]; then
    echo "  FAILED: help text should not expose removed commands" >> "$ERROR_FILE"
  fi
}

test_help_flags_exit_zero() {
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -f -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -q -h
  assert_exit_code 0 bash "$DOTFILE_CMD" -d -f -q -h
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --force --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --quiet --help
  assert_exit_code 0 bash "$DOTFILE_CMD" --help
}

test_unknown_command_fails() {
  assert_exit_code 1 bash "$DOTFILE_CMD" nonsense_command
}

test_removed_commands_fail() {
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry zsh
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry tmux
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry ai
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry extras
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry symlinks
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry languages
  assert_exit_code 1 bash "$DOTFILE_CMD" --dry verify
}
