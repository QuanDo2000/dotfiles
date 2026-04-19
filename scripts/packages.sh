#!/bin/bash
set -eo pipefail

# Fetch a URL with retry + exponential backoff. Useful for GitHub API calls
# which are rate-limited to 60 req/hr unauthenticated.
# Usage: http_get_retry <url> [output-file]
function http_get_retry {
  local url="$1" out="${2:-}"
  local attempt=1 max=4 delay=2
  while (( attempt <= max )); do
    if [[ -n "$out" ]]; then
      if curl -sfL --retry 2 -o "$out" "$url"; then return 0; fi
    else
      if curl -sfL --retry 2 "$url"; then return 0; fi
    fi
    if (( attempt < max )); then
      info "curl $url failed (attempt $attempt/$max); retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

function install_font_debian {
  # https://medium.com/source-words/how-to-manually-install-update-and-uninstall-fonts-on-linux-a8d09a3853b0
  info "Installing Fira Code..."
  if [[ "$DRY" == "false" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    if [ ! -f "$HOME/.local/share/fonts/FiraCodeNerdFont-Regular.ttf" ]; then
      cd "$HOME/.local/share/fonts" || fail "Failed to enter fonts directory"
      curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf \
        || fail "Failed to download Fira Code font"
      command -v fc-cache >/dev/null 2>&1 && fc-cache -f -v
      cd "$HOME" || fail "Failed to return to home directory"
    else
      info "Already installed font Fira Code"
    fi
  fi
  success "Finished installing Fira Code"
}

# Install or update neovim from GitHub releases (Linux only; Mac uses brew).
# Usage: setup_neovim [--update]
function setup_neovim {
  if is_mac; then
    return
  fi
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} neovim..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v nvim >/dev/null 2>&1; then
      info "Already installed neovim"
      return
    fi
    curl -fLO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz \
      || fail "Failed to download Neovim"
    sudo rm -rf /opt/nvim-linux-x86_64
    sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz || fail "Failed to extract Neovim"
    rm -f nvim-linux-x86_64.tar.gz
  fi
  success "Finished neovim"
}

# Install or update lazygit from GitHub releases.
# Usage: setup_lazygit [--update]
function setup_lazygit {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} lazygit..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v lazygit >/dev/null 2>&1; then
      info "Already installed lazygit"
      return
    fi
    local lazygit_json
    lazygit_json="$(http_get_retry "https://api.github.com/repos/jesseduffield/lazygit/releases/latest")" \
      || fail "Failed to fetch lazygit version (GitHub API unreachable or rate-limited)"
    LAZYGIT_VERSION="$(echo "$lazygit_json" | grep -Po '"tag_name": "v\K[^"]*')" \
      || fail "Failed to parse lazygit version"
    curl -fLo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
      || fail "Failed to download lazygit"
    tar xf lazygit.tar.gz lazygit || fail "Failed to extract lazygit"
    sudo install lazygit /usr/local/bin || fail "Failed to install lazygit"
    rm -f lazygit.tar.gz lazygit
  fi
  success "Finished lazygit"
}

# Install or update zoxide via its install script.
# Usage: setup_zoxide [--update]
function setup_zoxide {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} zoxide..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v zoxide >/dev/null 2>&1; then
      info "Already installed zoxide"
      return
    fi
    # Download to a temp file first so the fetch and execution are distinct
    # steps — avoids the classic `curl | sh` anti-pattern where a truncated
    # download still executes whatever partial script arrived.
    local tmp
    tmp="$(mktemp -t zoxide-install.XXXXXX.sh)" || fail "Failed to create temp file"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN
    http_get_retry "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh" "$tmp" \
      || fail "Failed to download zoxide installer"
    # Sanity-check: the installer should be a shell script.
    head -n1 "$tmp" | grep -q '^#!' \
      || fail "Downloaded zoxide installer does not look like a shell script"
    sh "$tmp" || fail "Failed to install zoxide"
  fi
  success "Finished zoxide"
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

# Bootstrap yay (AUR helper) on Arch. Clones yay-bin from the AUR and builds
# it with makepkg. Idempotent: no-op if yay is already on PATH.
# Usage: setup_yay
function setup_yay {
  info "Installing yay..."
  if [[ "$DRY" == "false" ]]; then
    if command -v yay >/dev/null 2>&1; then
      info "Already installed yay"
      success "Finished yay"
      return
    fi
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      fail "setup_yay must not run as root (makepkg refuses root)"
    fi
    command -v git >/dev/null 2>&1 || fail "git required for setup_yay"
    command -v makepkg >/dev/null 2>&1 || fail "makepkg required for setup_yay (install base-devel)"

    local build_dir="/tmp/yay-bin"
    rm -rf "$build_dir"
    git clone https://aur.archlinux.org/yay-bin.git "$build_dir" \
      || fail "Failed to clone yay-bin AUR repo"
    (cd "$build_dir" && makepkg -si --noconfirm) \
      || fail "Failed to build/install yay-bin"
    rm -rf "$build_dir"
  fi
  success "Finished yay"
}

DEBIAN_PACKAGES=(
  build-essential libssl-dev zlib1g-dev libbz2-dev
  libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils
  tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
  unzip zsh vim tmux fontconfig fzf fd-find ripgrep
)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_lazygit --update
    setup_zoxide --update
  fi
  success "Finished update for Debian"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_lazygit
    setup_neovim
    setup_zoxide

    setup_fdfind
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl wget git unzip zsh vim tmux fontconfig
  fzf fd ripgrep lazygit ttf-firacode-nerd zoxide
  gnupg wl-clipboard openssh lua51 luarocks nvm
  tree-sitter-cli
)

function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
  fi
  success "Finished update for Arch Linux"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}" \
      || fail "Failed to install Arch packages"

    setup_neovim
    setup_fdfind
  fi
  success "Finished install for Arch Linux"
}

MAC_BREW_PACKAGES=(
  bash wget tmux git vim neovim fzf fd ripgrep gcc font-fira-code-nerd-font
  gnupg pinentry-mac jesseduffield/lazygit/lazygit ast-grep zoxide
)
MAC_BREW_CASKS=(ghostty)

function update_mac {
  info "Updating packages for Mac..."
  if [[ "$DRY" == "false" ]]; then
    brew update || fail "Failed to update brew"
    brew upgrade || fail "Failed to upgrade brew packages"
  fi
  success "Finished update for Mac"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install "${MAC_BREW_PACKAGES[@]}"
    brew install --cask "${MAC_BREW_CASKS[@]}"
  fi
  success "Finished install for Mac"
}

function set_zsh_default {
  info "Changing default shell to zsh..."
  if [[ "$DRY" == "false" ]]; then
    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [[ -z "$zsh_path" ]]; then
      info "zsh not installed; skipping default shell change"
    elif [[ "$SHELL" == "$zsh_path" || "$(basename "$SHELL")" == "zsh" ]]; then
      info "Already has zsh as default shell"
    else
      chsh -s "$zsh_path"
    fi
  fi
  success "Finished changing zsh as default"
}

function update_packages {
  info "Updating packages..."
  case "$(detect_platform)" in
    debian)  update_debian ;;
    arch)    update_arch ;;
    mac)     update_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  success "Finished update"
}

function install_packages {
  info "Installing packages..."
  case "$(detect_platform)" in
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  set_zsh_default
  success "Finished install"
}
