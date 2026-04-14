#!/bin/bash
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
  assert_contains "$output" "Finished install for Mac"
}

test_install_mac_dry_run_does_not_install_ghostty() {
  local output
  output=$(install_mac 2>&1)

  if [[ "$output" == *"ghostty"* ]]; then
    echo "  FAILED: dry run should not mention ghostty (brew not called)" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# install_packages on Darwin
# ---------------------------------------------------------------------------

test_install_packages_mac_calls_set_zsh_default() {
  local output
  output=$(install_packages 2>&1)

  assert_contains "$output" "Changing default shell to zsh"
}

# ---------------------------------------------------------------------------
# set_zsh_default
# ---------------------------------------------------------------------------

test_set_zsh_default_dry_run() {
  local output
  output=$(set_zsh_default 2>&1)

  assert_contains "$output" "Changing default shell to zsh"
  assert_contains "$output" "Finished changing zsh as default"
}

test_set_zsh_default_already_zsh() {
  # chsh is not available on Git Bash; set_zsh_default relies on it.
  is_windows_bash && return 0
  DRY=false
  # Provide a fake zsh on PATH so `command -v zsh` resolves in environments
  # (e.g. minimal CI containers) where zsh isn't installed.
  local fake_bin="$TEST_TMPDIR/fakebin"
  mkdir -p "$fake_bin"
  printf '#!/bin/sh\n' > "$fake_bin/zsh"
  chmod +x "$fake_bin/zsh"
  local ORIG_PATH="$PATH"
  export PATH="$fake_bin:$PATH"
  SHELL="$fake_bin/zsh"
  export SHELL

  local output
  output=$(set_zsh_default 2>&1)
  export PATH="$ORIG_PATH"

  assert_contains "$output" "Already has zsh as default shell"
}

# ---------------------------------------------------------------------------
# install_extras (oh-my-zsh, zsh plugins, tmux plugins)
# ---------------------------------------------------------------------------

test_install_oh_my_zsh_dry_run() {
  local output
  output=$(install_oh_my_zsh 2>&1)

  assert_contains "$output" "Installing oh-my-zsh"
  assert_contains "$output" "Finished installing oh-my-zsh"
}

test_install_oh_my_zsh_already_installed() {
  DRY=false
  mkdir -p "$HOME/.oh-my-zsh"

  local output
  output=$(install_oh_my_zsh 2>&1)

  assert_contains "$output" "oh-my-zsh already installed"
}

test_install_zsh_plugins_dry_run() {
  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Installing zsh plugins"
  assert_contains "$output" "Finished installing zsh plugins"
}

test_install_zsh_plugins_already_installed() {
  DRY=false
  local custom="$HOME/.oh-my-zsh/custom/plugins"
  mkdir -p "$custom/zsh-autosuggestions"
  mkdir -p "$custom/fast-syntax-highlighting"
  mkdir -p "$custom/fzf-tab"

  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Finished installing zsh plugins"
}

test_install_zsh_plugins_fails_without_omz() {
  DRY=false
  rm -rf "$HOME/.oh-my-zsh"

  local exit_code=0
  (install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_zsh_plugins should fail when oh-my-zsh missing" >> "$ERROR_FILE"
  fi
}

test_install_tmux_plugins_dry_run() {
  local output
  output=$(install_tmux_plugins 2>&1)

  assert_contains "$output" "Installing tmux plugins"
  assert_contains "$output" "Finished installing tmux plugins"
}

test_install_tmux_plugins_tpm_already_installed() {
  DRY=false
  mkdir -p "$HOME/.tmux/plugins/tpm/bin"
  echo '#!/bin/bash' > "$HOME/.tmux/plugins/tpm/bin/install_plugins"
  chmod +x "$HOME/.tmux/plugins/tpm/bin/install_plugins"

  local output
  output=$(install_tmux_plugins 2>&1)

  assert_contains "$output" "Already installed TPM"
}

test_install_extras_dry_run() {
  local output
  output=$(install_extras 2>&1)

  assert_contains "$output" "Installing oh-my-zsh"
  assert_contains "$output" "Installing zsh plugins"
  assert_contains "$output" "Installing tmux plugins"
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
  assert_contains "$output" "Installing oh-my-zsh"
  assert_contains "$output" "Setting up symlinks"
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

  assert_contains "$output" "Installing oh-my-zsh"
  assert_contains "$output" "Installing zsh plugins"
  assert_contains "$output" "Installing tmux plugins"
}

test_dotfile_symlinks_command_mac() {
  create_dotfiles_dirs

  local output
  output=$(bash "$DOTFILE_CMD" --dry symlinks 2>&1)

  assert_contains "$output" "Setting up symlinks"
  assert_contains "$output" "dotfiles/config/mac"
}
