#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh verify.sh
}

teardown() {
  cleanup_test_env
}

test_verify_tool_found() {
  local output
  output=$(
    if command -v bash >/dev/null 2>&1; then
      success "bash found: $(command -v bash)"
    else
      fail_soft "bash not found"
    fi
  )
  assert_contains "$output" "bash found"
}

test_verify_tool_missing() {
  local output
  output=$(
    if command -v nonexistent_tool_xyz >/dev/null 2>&1; then
      success "found"
    else
      fail_soft "nonexistent_tool_xyz not found"
    fi
  )
  assert_contains "$output" "nonexistent_tool_xyz not found"
}

test_verify_symlink_valid() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.vimrc"
  ln -s "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"

  if [[ ! -L "$HOME/.vimrc" ]]; then
    echo "  Expected $HOME/.vimrc to be a symlink" >> "$ERROR_FILE"
    return
  fi
  local link_target
  link_target="$(readlink "$HOME/.vimrc")"
  assert_contains "$link_target" "$DOTFILES_DIR"
}

test_verify_file_not_symlink() {
  echo "not a symlink" > "$HOME/.vimrc"
  if [[ -L "$HOME/.vimrc" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$HOME/.vimrc"
}

test_verify_error_count() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "issue(s) found"
}

test_verify_oh_my_zsh_detected() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/.oh-my-zsh"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "oh-my-zsh installed"
}

test_verify_oh_my_zsh_missing() {
  mkdir -p "$DOTFILES_DIR"
  rm -rf "$HOME/.oh-my-zsh"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "oh-my-zsh not installed"
}

test_verify_zsh_plugin_detected() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "zsh plugin: zsh-autosuggestions"
}

test_verify_tpm_detected() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/.tmux/plugins/tpm"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "TPM installed"
}

test_verify_symlink_wrong_target() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/other"
  echo "content" > "$HOME/other/.vimrc"
  ln -s "$HOME/other/.vimrc" "$HOME/.vimrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "expected"
}

test_verify_zshrc_exists() {
  mkdir -p "$DOTFILES_DIR/config/unix"
  echo "zshrc content" > "$DOTFILES_DIR/config/unix/.zshrc"
  echo "zshrc content" > "$HOME/.zshrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" ".zshrc matches source"
}

test_verify_zshrc_source_missing() {
  mkdir -p "$DOTFILES_DIR"
  # .zshrc exists in HOME but source file does not
  echo "zshrc content" > "$HOME/.zshrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "source not found"
}
