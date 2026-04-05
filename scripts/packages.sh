#!/bin/bash

function install_font_debian {
  # https://medium.com/source-words/how-to-manually-install-update-and-uninstall-fonts-on-linux-a8d09a3853b0
  info "Installing Fira Code..."
  if [[ "$DRY" == "false" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    if [ ! -f "$HOME/.local/share/fonts/FiraCodeNerdFont-Regular.ttf" ]; then
      cd "$HOME/.local/share/fonts" && curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf
      fc-cache -f -v
      cd "$HOME" || return
    else
      info "Already installed font Fira Code"
    fi
  fi
  success "Finished installing Fira Code"
}

function install_neovim {
  # On Mac, neovim is installed via brew in install_mac
  if [[ "$(uname)" == "Darwin" ]]; then
    return
  fi
  info "Installing neovim..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v nvim >/dev/null 2>&1; then
      # Install latest Neovim
      curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
      sudo rm -rf /opt/nvim-linux-x86_64
      sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
      rm -rf nvim-linux-x86_64.tar.gz
    else
      info "Already installed neovim"
    fi
  fi
  success "Finished installing neovim"
}

function install_lazygit {
  info "Installing lazygit..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v lazygit >/dev/null 2>&1; then
      LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
      tar xf lazygit.tar.gz lazygit
      sudo install lazygit /usr/local/bin
      rm -rf lazygit.tar.gz lazygit
    else
      info "Already installed lazygit"
    fi
  fi
  success "Finished installing lazygit"
}

function install_zoxide {
  info "Installing zoxide..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v zoxide >/dev/null 2>&1; then
      curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    else
      info "Already installed zoxide"
    fi
  fi
  success "Finished installing zoxide"
}

function setup_fdfind {
  info "Ensuring 'fd' is available in '.local/bin'..."
  if [[ "$DRY" == "false" ]]; then
    mkdir -p "$HOME/.local/bin"
    # Preferred executable is 'fd'; on Debian-based systems it's 'fdfind'
    if command -v fd >/dev/null 2>&1; then
      info "'fd' already available on PATH"
      # create a user-local symlink to ensure consistent path
      if [ ! -L "$HOME/.local/bin/fd" ]; then
        ln -s "$(command -v fd)" "$HOME/.local/bin/fd" || true
      fi
    elif command -v fdfind >/dev/null 2>&1; then
      if [ ! -L "$HOME/.local/bin/fd" ]; then
        ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      else
        info "Already symlinked fdfind to '.local/bin/fd'"
      fi
    else
      info "fd not found on system; skipping symlink. Install 'fd' (ripgrep/ fd) manually or via your package manager"
    fi
  fi
  success "Finished ensuring fd in '.local/bin'"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
      libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils \
      tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
      unzip zsh vim tmux fontconfig fzf fd-find ripgrep \
      || fail "Failed to install Debian packages"

    install_font_debian
    install_lazygit
    install_neovim
    install_zoxide

    setup_fdfind
  fi
  success "Finished install for Debian"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    # Update system and install packages
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    sudo pacman -S --needed --noconfirm \
      base-devel curl wget git unzip zsh vim tmux fontconfig \
      fzf fd ripgrep lazygit ttf-firacode-nerd zoxide \
      gnupg wl-clipboard openssh lua51 luarocks nvm \
      tree-sitter-cli \
      || fail "Failed to install Arch packages"

    install_neovim
    setup_fdfind
  fi
  success "Finished install for Arch Linux"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew update
    brew install bash wget tmux git vim neovim fzf fd ripgrep gcc font-fira-code-nerd-font \
      gnupg pinentry-mac jesseduffield/lazygit/lazygit ast-grep zoxide

    # Ghostty
    brew install --cask ghostty
  fi
  success "Finished install for Mac"
}

function set_zsh_default {
  info "Changing default shell to zsh..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$SHELL" != "$(command -v zsh)" ]]; then
      chsh -s "$(command -v zsh)"
    else
      info "Already has zsh as default shell"
    fi
  fi
  success "Finished changing zsh as default"
}

function install_packages {
  info "Installing packages..."
  if [[ "$(uname)" == "Linux" ]]; then
    if [[ -f "/etc/os-release" ]]; then
      source /etc/os-release
      if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
        install_debian
      elif [[ "$ID" == "arch" || "$ID_LIKE" == *"arch"* ]]; then
        install_arch
      else
        fail "Unknown Linux distribution: $ID"
      fi
    else
      fail "Could not detect Linux distribution."
    fi
  elif [[ "$(uname)" == "Darwin" ]]; then
    install_mac
  else
    fail "Unsupported system: $(uname)"
  fi

  set_zsh_default
  success "Finished install"
}
