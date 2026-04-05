#!/bin/bash

function verify {
  local errors=0

  info "Verifying installed tools..."
  for cmd in git zsh vim nvim tmux fzf fd rg lazygit zoxide; do
    if command -v "$cmd" >/dev/null 2>&1; then
      success "$cmd found: $(command -v "$cmd")"
    else
      fail_soft "$cmd not found"
      errors=$((errors + 1))
    fi
  done

  info "Verifying oh-my-zsh..."
  if [ -d "$HOME/.oh-my-zsh" ]; then
    success "oh-my-zsh installed"
  else
    fail_soft "oh-my-zsh not installed"
    errors=$((errors + 1))
  fi

  info "Verifying zsh plugins..."
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  for plugin in zsh-autosuggestions fast-syntax-highlighting fzf-tab; do
    if [ -d "$zsh_custom/plugins/$plugin" ]; then
      success "zsh plugin: $plugin"
    else
      fail_soft "zsh plugin missing: $plugin"
      errors=$((errors + 1))
    fi
  done

  info "Verifying tmux plugins..."
  if [ -d "$HOME/.tmux/plugins/tpm" ]; then
    success "TPM installed"
  else
    fail_soft "TPM not installed"
    errors=$((errors + 1))
  fi

  info "Verifying symlinks..."
  local dotfiles_dir="$HOME/dotfiles"
  for f in .zshrc .zshrc.base .tmux.conf .vimrc .gitconfig .zprofile; do
    local target="$HOME/$f"
    if [ -L "$target" ]; then
      local link_target
      link_target="$(readlink "$target")"
      if [[ "$link_target" == "$dotfiles_dir"* ]]; then
        success "$f -> $link_target"
      else
        fail_soft "$f points to $link_target (expected $dotfiles_dir/...)"
        errors=$((errors + 1))
      fi
    elif [ -f "$target" ]; then
      fail_soft "$f exists but is not a symlink"
      errors=$((errors + 1))
    else
      fail_soft "$f not found"
      errors=$((errors + 1))
    fi
  done

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
  else
    info "$errors issue(s) found" --force
  fi
}
