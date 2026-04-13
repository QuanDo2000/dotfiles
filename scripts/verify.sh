#!/bin/bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Binaries expected on PATH after install_packages has run.
# Keep in sync with scripts/packages.sh (DEBIAN_PACKAGES / ARCH_PACKAGES / MAC_BREW_PACKAGES).
REQUIRED_TOOLS=(git zsh vim nvim tmux fzf fd rg lazygit zoxide)

# Symlinked dotfiles under $HOME (resolved to $DOTFILES_DIR/...).
# Keep in sync with scripts/symlinks.sh and the shared/unix layout.
REQUIRED_SYMLINKS=(.zshrc.base .tmux.conf .vimrc .gitconfig .zprofile)

# Helper: check that a command exists on PATH.
# Increments $errors on failure.
_check_tool() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    success "$cmd found: $(command -v "$cmd")"
  else
    fail_soft "$cmd not found"
    errors=$((errors + 1))
  fi
}

# Helper: check that a directory exists.
# $1 = path, $2 = label shown on success, $3 = label shown on failure.
_check_dir() {
  local path="$1" ok_msg="$2" fail_msg="$3"
  if [ -d "$path" ]; then
    success "$ok_msg"
  else
    fail_soft "$fail_msg"
    errors=$((errors + 1))
  fi
}

# Helper: check that a file is a symlink pointing into DOTFILES_DIR.
_check_symlink() {
  local name="$1"
  local target="$HOME/$name"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(readlink "$target")"
    if [[ "$link_target" == "$DOTFILES_DIR"* ]]; then
      success "$name -> $link_target"
    else
      fail_soft "$name points to $link_target (expected $DOTFILES_DIR/...)"
      errors=$((errors + 1))
    fi
  elif [ -f "$target" ]; then
    fail_soft "$name exists but is not a symlink"
    errors=$((errors + 1))
  else
    fail_soft "$name not found"
    errors=$((errors + 1))
  fi
}

function verify {
  local errors=0

  info "Verifying installed tools..."
  for cmd in "${REQUIRED_TOOLS[@]}"; do
    _check_tool "$cmd"
  done

  info "Verifying oh-my-zsh..."
  _check_dir "$HOME/.oh-my-zsh" "oh-my-zsh installed" "oh-my-zsh not installed"

  info "Verifying zsh plugins..."
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for plugin in zsh-autosuggestions fast-syntax-highlighting fzf-tab; do
    _check_dir "$zsh_custom/plugins/$plugin" "zsh plugin: $plugin" "zsh plugin missing: $plugin"
  done

  info "Verifying tmux plugins..."
  _check_dir "$HOME/.tmux/plugins/tpm" "TPM installed" "TPM not installed"

  info "Verifying symlinks..."
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    _check_symlink "$f"
  done

  info "Verifying copied files..."
  local source="$DOTFILES_DIR/unix/.zshrc"
  local target="$HOME/.zshrc"
  if [ -f "$target" ]; then
    if [ ! -f "$source" ]; then
      info ".zshrc exists but source not found at $source"
    elif diff -q "$source" "$target" >/dev/null 2>&1; then
      success ".zshrc matches source"
    else
      info ".zshrc exists but differs from source (local edits are expected)"
    fi
  else
    fail_soft ".zshrc not found"
    errors=$((errors + 1))
  fi

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
  else
    info "$errors issue(s) found" --force
  fi
}
