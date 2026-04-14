#!/bin/bash
set -eo pipefail

function install_oh_my_zsh {
  info "Installing oh-my-zsh..."
  if [[ "$DRY" == "false" ]]; then
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
      info "oh-my-zsh already installed"
    fi
  fi
  success "Finished installing oh-my-zsh"
}

# Clone a git repo into $dest if $dest doesn't already exist.
# Usage: clone_if_missing <name> <repo-url> <dest> [git-args...]
function clone_if_missing {
  local name="$1" repo="$2" dest="$3"
  shift 3
  info "Installing $name..."
  if [ ! -d "$dest" ]; then
    git clone "$@" "$repo" "$dest" || fail "Failed to clone $name"
  fi
  success "Finished installing $name"
}

function install_zsh_plugins {
  info "Installing zsh plugins..."
  if [[ "$DRY" == "false" ]]; then
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      fail "oh-my-zsh not installed."
    fi
    local plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    clone_if_missing "zsh-autosuggestions" \
      "https://github.com/zsh-users/zsh-autosuggestions" \
      "$plugins_dir/zsh-autosuggestions"
    clone_if_missing "fast-syntax-highlighting" \
      "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" \
      "$plugins_dir/fast-syntax-highlighting"
    clone_if_missing "fzf-tab" \
      "https://github.com/Aloxaf/fzf-tab" \
      "$plugins_dir/fzf-tab"
  fi
  success "Finished installing zsh plugins"
}

function install_tmux_plugins {
  info "Installing tmux plugins..."
  if [[ "$DRY" == "false" ]]; then
    info "Installing TPM..."
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
        || fail "Failed to clone TPM"
      "$HOME/.tmux/plugins/tpm/bin/install_plugins"
    else
      info "Already installed TPM"
    fi
    success "Finished installing TPM"

    clone_if_missing "catppuccin for tmux" \
      "https://github.com/catppuccin/tmux.git" \
      "$HOME/.tmux/plugins/catppuccin/tmux" \
      -b v2.1.2
  fi
  success "Finished installing tmux plugins"
}

function install_extras {
  info "Installing extras"
  install_oh_my_zsh
  install_zsh_plugins
  install_tmux_plugins
  success "Finished installing extras"
}
