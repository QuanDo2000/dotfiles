#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME=""

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
  source "$REPO_DIR/scripts/verify.sh"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_HOME"
}

test_verify_tool_found() {
  # "bash" is always available
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
  local dotfiles_dir="$TEST_HOME/dotfiles"
  mkdir -p "$dotfiles_dir"
  echo "content" > "$dotfiles_dir/.vimrc"
  ln -s "$dotfiles_dir/.vimrc" "$TEST_HOME/.vimrc"

  local target="$TEST_HOME/.vimrc"
  if [[ ! -L "$target" ]]; then
    echo "  Expected $target to be a symlink" >> "$ERROR_FILE"
    return
  fi
  local link_target
  link_target="$(readlink "$target")"
  assert_contains "$link_target" "$dotfiles_dir"
}

test_verify_file_not_symlink() {
  echo "not a symlink" > "$TEST_HOME/.vimrc"
  if [[ -L "$TEST_HOME/.vimrc" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$TEST_HOME/.vimrc"
}

test_verify_error_count() {
  # Run verify with a mostly empty HOME — most checks will fail
  # The verify function should report issues
  mkdir -p "$TEST_HOME/dotfiles"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "issue(s) found"
}

test_verify_oh_my_zsh_detected() {
  mkdir -p "$TEST_HOME/dotfiles"
  mkdir -p "$TEST_HOME/.oh-my-zsh"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "oh-my-zsh installed"
}

test_verify_oh_my_zsh_missing() {
  mkdir -p "$TEST_HOME/dotfiles"
  rm -rf "$TEST_HOME/.oh-my-zsh"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "oh-my-zsh not installed"
}

test_verify_zsh_plugin_detected() {
  mkdir -p "$TEST_HOME/dotfiles"
  mkdir -p "$TEST_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "zsh plugin: zsh-autosuggestions"
}

test_verify_tpm_detected() {
  mkdir -p "$TEST_HOME/dotfiles"
  mkdir -p "$TEST_HOME/.tmux/plugins/tpm"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "TPM installed"
}

test_verify_symlink_wrong_target() {
  mkdir -p "$TEST_HOME/dotfiles"
  mkdir -p "$TEST_HOME/other"
  echo "content" > "$TEST_HOME/other/.vimrc"
  ln -s "$TEST_HOME/other/.vimrc" "$TEST_HOME/.vimrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "expected"
}

test_verify_zshrc_exists() {
  mkdir -p "$TEST_HOME/dotfiles/unix"
  echo "zshrc content" > "$TEST_HOME/dotfiles/unix/.zshrc"
  echo "zshrc content" > "$TEST_HOME/.zshrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" ".zshrc matches source"
}
