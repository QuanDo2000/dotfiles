#!/bin/bash

# Global variables
DRY=false

info() {
  printf '\r  [ \033[00;34m..\033[0m ] %s\n' "$1"
}

user() {
  printf '\r  [ \033[0;33m??\033[0m ] %b\n' "$1"
}

success() {
  printf '\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n' "$1"
}

fail() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
  echo ''
  exit 1
}

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
  info "Installing neovim..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v nvim >/dev/null 2>&1; then
      # Install latest Neovim
      curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
      sudo rm -rf /opt/nvim
      sudo tar -C /opt -xzf nvim-linux64.tar.gz
      rm -rf nvim-linux64.tar.gz
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
    sudo apt update -y
    sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
      libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils \
      tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
      unzip zsh vim tmux fontconfig fzf fd-find ripgrep

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
    sudo pacman -Syu --noconfirm

    sudo pacman -S --needed --noconfirm \
      base-devel curl wget git unzip zsh vim tmux fontconfig \
      fzf fd ripgrep neovim lazygit ttf-firacode-nerd zoxide \
      gnupg wl-clipboard

    # Reuse existing helpers
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
    if [[ "$SHELL" != "$(which zsh)" ]]; then
      chsh -s "$(which zsh)"
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

function clone_repo {
  info "Getting dotfiles repo..."
  if [[ "$DRY" == "false" ]]; then
    if [ ! -d "$HOME/dotfiles" ]; then
      cd "$HOME" || return
      git clone https://github.com/QuanDo2000/dotfiles.git
      info "Finished cloning dotfiles repo"
    else
      cd "$HOME/dotfiles" || return
      git pull
      info "Finished pulling dotfiles repo"
    fi
  fi
  success "Finished getting repo"
}

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
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
      fi
      success "Finished installing zsh-autosuggestions"

      info "Installing fast-syntax-highlighting..."
      if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting" ]; then
        git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
          "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting"
      fi
      success "Finished installing fast-syntax-highlighting"

      info "Installing fzf-tab..."
      if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab" ]; then
        git clone https://github.com/Aloxaf/fzf-tab "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/fzf-tab"
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
      git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
      "$HOME/.tmux/plugins/tpm/bin/install_plugins"
    else
      info "Already installed TPM"
    fi
    success "Finished installing TPM"

    info "Installing catppuccin for tmux..."
    if [ ! -d "$HOME/.tmux/plugins/catppuccin" ]; then
      git clone -b v2.1.2 https://github.com/catppuccin/tmux.git ~/.tmux/plugins/catppuccin/tmux
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

function link_files {
  local src=$1 dst=$2
  local overwrite=false backup=false skip=false action=false
  info "Linking $src to $dst"
  if [[ "$DRY" == "true" ]]; then
    return
  fi

  if [ -f "$dst" ] || [ -d "$dst" ] || [ -L "$dst" ]; then
    if [[ "$overwrite_all" == "false" && "$backup_all" == "false" && "$skip_all" == "false" ]]; then
      local current_src
      current_src="$(readlink "$dst")"

      if [[ "$current_src" == "$src" ]]; then
        skip=true
      else
        user "File already exists: $dst ($(basename "$src")), what do you want to do?\n\
                    [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
        read -n 1 -r action

        case "$action" in
        o)
          overwrite=true
          ;;
        O)
          overwrite_all=true
          ;;
        b)
          backup=true
          ;;
        B)
          backup_all=true
          ;;
        s)
          skip=true
          ;;
        S)
          skip_all=true
          ;;
        *) ;;
        esac
      fi
    fi

    if [[ "$overwrite" == "true" || "$overwrite_all" == "true" ]]; then
      rm -rf "$dst"
      success "Removed $dst"
    fi

    if [[ "$backup" == "true" || "$backup_all" == "true" ]]; then
      mv "$dst" "${dst}.backup"
      success "Moved $dst to ${dst}.backup"
    fi

    if [[ "$skip" == "true" || "$skip_all" == "true" ]]; then
      success "Skipped $src"
    fi
  fi

  if [[ "$skip" != "true" && "$skip_all" != "true" ]]; then
    ln -s "$1" "$2"
    success "Linked $1 to $2"
  fi
}

function setup_symlinks_folder {
  local root=$1
  info "Setting up symlinks for $root..."

  if [[ ! -d "$root" ]]; then
    info "$root doesn't exist"
    return
  fi

  # Setup symlinks for direct files
  while IFS= read -r -d '' src <&3; do
    dst="$HOME/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root" -maxdepth 1 -type f -print0)

  # Setup symlinks for config folders
  if [[ ! -d "$root/config" ]]; then
    info "$root/config doesn't exist"
    return
  fi
  if [[ ! -d "$HOME/.config" ]]; then
    info "$HOME/.config doesn't exist. Creating folder..."
    mkdir -p "$HOME/.config"
  fi
  while IFS= read -r -d '' src <&3; do
    dst="$HOME/.config/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root/config" -mindepth 1 -maxdepth 1 -type d -print0)

  success "Finished setting up symlinks for $root"
}

function setup_symlinks {
  local overwrite_all=false backup_all=false skip_all=false

  setup_symlinks_folder "$HOME/dotfiles/shared"
  setup_symlinks_folder "$HOME/dotfiles/unix"
  if [[ "$(uname)" == "Linux" ]] && [[ -d "$HOME/dotfiles/linux" ]]; then
    setup_symlinks_folder "$HOME/dotfiles/linux"
  elif [[ "$(uname)" == "Darwin" ]]; then
    setup_symlinks_folder "$HOME/dotfiles/mac"
  fi
}

function setup_dotfiles {
  info "Setting up dotfiles..."
  install_packages
  clone_repo
  install_extras
  setup_symlinks
  success "Done!"
}

if [ "$1" = "--dry" ] || [ "$1" = "-d" ]; then
  DRY=true
  setup_dotfiles
elif [ "$1" = "--install" ] || [ "$1" = "-i" ]; then
  install_packages
  install_extras
elif [ "$1" = "--symlinks" ] || [ "$1" = "-s" ]; then
  setup_symlinks
else
  setup_dotfiles
fi
exit 0
