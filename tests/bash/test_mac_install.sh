#!/usr/bin/env bash
# Tests for the Mac installation path.
# All tests mock uname to return "Darwin" via setup() so they exercise
# Mac-specific branches regardless of the host OS.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env true   # DRY=true by default
  source_scripts utils.sh packages.sh
  mock_uname Darwin
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# install_mac
# ---------------------------------------------------------------------------

test_install_mac_dry_run_no_brew_calls() {
  local output
  output=$(install_mac 2>&1)

  assert_contains "$output" "Installing packages and programs for Mac"
  assert_contains "$output" "sudo HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
  assert_contains "$output" "Finished install for Mac"
}

test_update_mac_dry_run_shows_darwin_rebuild() {
  local output
  output=$(update_mac 2>&1)

  assert_contains "$output" "Updating packages for Mac"
  assert_contains "$output" "sudo HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
}

test_install_mac_dry_run_does_not_install_ghostty() {
  local output
  output=$(install_mac 2>&1)

  if [[ "$output" == *"ghostty"* ]]; then
    echo "  FAILED: dry run should not mention ghostty (brew not called)" >> "$ERROR_FILE"
  fi
}

test_install_mac_bootstraps_nix_darwin_without_brew() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|darwin-rebuild|brew) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  install_mac >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "HOME=/var/root nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $DOTFILES_DIR#mac"
  assert_not_contains "$output" "brew"

  unset -f command _install_lix _load_nix_profile sudo
}

test_update_mac_switches_existing_darwin_rebuild() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|darwin-rebuild) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  _load_nix_profile() { :; }
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  update_mac >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
  assert_not_contains "$output" "brew"

  unset -f command _load_nix_profile sudo
}

test_ensure_nix_loads_profile_before_installing() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  local nix_available=false
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "nix" ]]; then
      [[ "$nix_available" == "true" ]]
      return
    fi
    builtin command "$@"
  }
  _load_nix_profile() {
    printf '%s\n' "load-profile" >> "$calls"
    nix_available=true
  }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }

  _ensure_nix

  local output
  output="$(<"$calls")"
  assert_contains "$output" "load-profile"
  assert_not_contains "$output" "install-lix"

  unset -f command _load_nix_profile _install_lix
}

test_load_nix_profile_tolerates_unset_zsh_version() {
  local profile_dir="$HOME/.nix-profile/etc/profile.d"
  mkdir -p "$profile_dir"
  printf 'if [[ -n "$ZSH_VERSION" ]]; then :; fi\n' > "$profile_dir/nix.sh"

  assert_exit_code 0 _load_nix_profile
}

# ---------------------------------------------------------------------------
# install_packages on Darwin
# ---------------------------------------------------------------------------

test_install_packages_mac_skips_chsh() {
  local output
  output=$(install_packages 2>&1)

  assert_contains "$output" "Shell is managed declaratively on mac; skipping chsh"
}

# ---------------------------------------------------------------------------
# set_zsh_default
# ---------------------------------------------------------------------------

test_set_zsh_default_skips_on_mac() {
  local output
  output=$(set_zsh_default 2>&1)

  assert_contains "$output" "Shell is managed declaratively on mac; skipping chsh"
  assert_contains "$output" "Finished changing zsh as default"
}

# ---------------------------------------------------------------------------
# Full Mac setup_dotfiles dry-run
# ---------------------------------------------------------------------------

test_setup_dotfiles_dry_run_mac() {
  source_scripts doctor.sh

  create_dotfiles_dirs
  echo "mac" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  function update_repo {
    info "Updating dotfiles repo..."
    success "Finished updating repo"
  }

  function setup_dotfiles {
    info "Setting up dotfiles..."
    install_packages
    update_repo
    success "Done!"
  }

  local output
  output=$(setup_dotfiles 2>&1)

  assert_contains "$output" "Setting up dotfiles"
  assert_contains "$output" "Installing packages and programs for Mac"
  assert_contains "$output" "Done!"
}

# ---------------------------------------------------------------------------
# dotfile CLI commands on Mac (dry-run)
# ---------------------------------------------------------------------------

test_dotfile_packages_command_mac() {
  mkdir -p "$HOME/.local/bin"
  local f src
  for f in .zshrc .tmux.conf .gitconfig; do
    case "$f" in
      .zshrc) src="$REPO_DIR/config/unix/.zshrc.base" ;;
      .gitconfig) src="$REPO_DIR/config/shared/$f" ;;
      *) src="$REPO_DIR/config/unix/$f" ;;
    esac
    ln -s "$src" "$HOME/$f"
  done
  ln -s "$DOTFILE_CMD" "$HOME/.local/bin/dotfile"
  with_nix_agent_tools

  local output
  output=$(DOTFILE_DOCTOR_SKIP_NIX_EVAL=true bash "$DOTFILE_CMD" --dry packages 2>&1)

  assert_contains "$output" "Mac"
}
