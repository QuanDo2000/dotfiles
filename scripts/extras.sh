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

function install_zsh_plugins {
  info "Installing zsh plugins..."
  if [[ "$DRY" == "false" ]]; then
    if [ -d "$HOME/.oh-my-zsh" ]; then
      info "Installing zsh-autosuggestions..."
      if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" \
          || fail "Failed to clone zsh-autosuggestions"
      fi
      success "Finished installing zsh-autosuggestions"

      info "Installing fast-syntax-highlighting..."
      if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting" ]; then
        git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
          "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting" \
          || fail "Failed to clone fast-syntax-highlighting"
      fi
      success "Finished installing fast-syntax-highlighting"

      info "Installing fzf-tab..."
      if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab" ]; then
        git clone https://github.com/Aloxaf/fzf-tab "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab" \
          || fail "Failed to clone fzf-tab"
      fi
      success "Finished installing fzf-tab"
    else
      fail "oh-my-zsh not installed."
    fi
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

    info "Installing catppuccin for tmux..."
    if [ ! -d "$HOME/.tmux/plugins/catppuccin" ]; then
      git clone -b v2.1.2 https://github.com/catppuccin/tmux.git ~/.tmux/plugins/catppuccin/tmux \
        || fail "Failed to clone catppuccin for tmux"
    else
      info "Already installed catppuccin for tmux"
    fi
    success "Finished installing catppuccin for tmux"
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
