#!/usr/bin/env bash
# Tests for the Mac installation path.
# All tests mock uname to return "Darwin" via setup() so they exercise
# Mac-specific branches regardless of the host OS.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env true   # DRY=true by default
  source_scripts utils.sh packages.sh extras.sh symlinks.sh
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
  setup_codex() { :; }
  setup_codebase_memory_mcp() { :; }

  install_mac >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "HOME=/var/root nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake $DOTFILES_DIR#mac"
  assert_not_contains "$output" "brew"

  unset -f command _install_lix _load_nix_profile sudo setup_codex setup_codebase_memory_mcp
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
  setup_codex() { :; }
  setup_codebase_memory_mcp() { :; }

  update_mac >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
  assert_not_contains "$output" "brew"

  unset -f command _load_nix_profile sudo setup_codex setup_codebase_memory_mcp
}

test_darwin_rebuild_cleans_old_plugin_dirs_before_switch() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  local zsh_plugin="$HOME/.local/share/zsh/plugins/zsh-autosuggestions"
  local tmux_plugin="$HOME/.tmux/plugins/tmux-yank"
  mkdir -p "$zsh_plugin/.git" "$zsh_plugin.before-home-manager/zsh-autosuggestions" \
    "$tmux_plugin/.git" "$tmux_plugin.before-home-manager/tmux-yank"
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

  _darwin_rebuild_switch >/dev/null 2>&1

  if [ -e "$zsh_plugin" ] || [ -e "$zsh_plugin.before-home-manager" ]; then
    echo "  FAILED: old zsh plugin dirs should be removed before darwin-rebuild" >> "$ERROR_FILE"
  fi
  if [ -e "$tmux_plugin" ] || [ -e "$tmux_plugin.before-home-manager" ]; then
    echo "  FAILED: old tmux plugin dirs should be removed before darwin-rebuild" >> "$ERROR_FILE"
  fi

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
# install_extras (zsh plugins, tmux plugins)
# ---------------------------------------------------------------------------

test_install_zsh_plugins_dry_run() {
  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Installing zsh plugins"
  assert_contains "$output" "Finished installing zsh plugins"
}

test_install_zsh_plugins_already_installed() {
  DRY=false
  local plugins_dir="$HOME/.local/share/zsh/plugins"
  mkdir -p "$plugins_dir/zsh-autosuggestions/.git"
  mkdir -p "$plugins_dir/fast-syntax-highlighting/.git"
  mkdir -p "$plugins_dir/fzf-tab/.git"

  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Finished installing zsh plugins"
}

test_install_tmux_plugins_dry_run() {
  local output
  output=$(install_tmux_plugins 2>&1)

  assert_contains "$output" "Installing tmux plugins"
  assert_contains "$output" "Finished installing tmux plugins"
}

test_install_tmux_plugins_already_installed() {
  DRY=false
  # Both plugins present with .git inside → clone_if_missing skips, no git call.
  mkdir -p "$HOME/.tmux/plugins/tmux-yank/.git" \
    "$HOME/.tmux/plugins/catppuccin/tmux/.git"

  local output
  output=$(install_tmux_plugins 2>&1)

  assert_contains "$output" "Finished installing tmux plugins"
}

test_install_extras_dry_run() {
  local output
  output=$(install_extras 2>&1)

  assert_contains "$output" "managed by Nix"
  assert_contains "$output" "Finished installing extras"
}

# ---------------------------------------------------------------------------
# Full Mac setup_dotfiles dry-run
# ---------------------------------------------------------------------------

test_setup_dotfiles_dry_run_mac() {
  source_scripts verify.sh

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
    install_extras
    setup_symlinks
    success "Done!"
  }

  local output
  output=$(setup_dotfiles 2>&1)

  assert_contains "$output" "Setting up dotfiles"
  assert_contains "$output" "Installing packages and programs for Mac"
  assert_contains "$output" "managed by Nix"
  assert_contains "$output" "Home Manager manages dotfile links"
  assert_contains "$output" "Done!"
}

# ---------------------------------------------------------------------------
# dotfile CLI commands on Mac (dry-run)
# ---------------------------------------------------------------------------

test_dotfile_packages_command_mac() {
  local output
  output=$(bash "$DOTFILE_CMD" --dry packages 2>&1)

  assert_contains "$output" "Mac"
}

test_dotfile_extras_command_dry() {
  local output
  output=$(bash "$DOTFILE_CMD" --dry extras 2>&1)

  assert_contains "$output" "managed by Nix"
}

test_dotfile_symlinks_command_mac() {
  create_dotfiles_dirs

  local output
  output=$(bash "$DOTFILE_CMD" --dry symlinks 2>&1)

  assert_contains "$output" "Home Manager manages dotfile links"
  assert_not_contains "$output" ".local/bin/dotfile"
}
