#!/bin/bash
set -eo pipefail

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

    local build_dir
    build_dir="$(mktemp -d -t yay-bin.XXXXXX)" || fail "Failed to create temp dir"
    # EXIT covers fail()'s exit 1 path; RETURN covers normal returns. Without
    # EXIT, every fail() in this function would leak $build_dir under /tmp.
    # shellcheck disable=SC2064
    trap "rm -rf '$build_dir'" EXIT RETURN
    git clone https://aur.archlinux.org/yay-bin.git "$build_dir" \
      || fail "Failed to clone yay-bin AUR repo"
    (cd "$build_dir" && makepkg -si --noconfirm) \
      || fail "Failed to build/install yay-bin"
  fi
  success "Finished yay"
}

# Install or update pwsh (PowerShell 7+). Dispatches by platform:
#   - debian: Microsoft apt repo via packages-microsoft-prod.deb
#   - arch:   yay -S powershell-bin (AUR)
#   - mac:    no-op (handled by MAC_BREW_CASKS)
# Usage: setup_pwsh [--update]
function setup_pwsh {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true

  local platform
  platform="$(detect_platform)"

  case "$platform" in
    mac) return ;;
    debian|arch) ;;
    *) return ;;
  esac

  info "${update:+Updating}${update:- Installing} pwsh..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v pwsh >/dev/null 2>&1; then
      info "Already installed pwsh"
      success "Finished pwsh"
      return
    fi
    case "$platform" in
      debian) _setup_pwsh_debian "$update" ;;
      arch)   _setup_pwsh_arch "$update" ;;
    esac
  fi
  success "Finished pwsh"
}

# Install or update pwsh on Debian/Ubuntu via Microsoft's apt repo.
# $1 = "true" for --update mode (skip repo bootstrap).
_setup_pwsh_debian() {
  local update="$1"
  local ms_list="/etc/apt/sources.list.d/microsoft-prod.list"

  if [[ ! -f "$ms_list" ]]; then
    local id="" version_id=""
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    version_id="${VERSION_ID:-}"
    local distro=""
    case "$id" in
      debian) distro="debian" ;;
      ubuntu) distro="ubuntu" ;;
      *)
        if [[ "${ID_LIKE:-}" == *ubuntu* ]]; then distro="ubuntu"
        elif [[ "${ID_LIKE:-}" == *debian* ]]; then distro="debian"
        fi
        ;;
    esac
    if [[ -z "$distro" || -z "$version_id" ]]; then
      info "pwsh: could not detect Debian/Ubuntu variant (ID=$id VERSION_ID=$version_id); skipping"
      return
    fi
    local deb_url="https://packages.microsoft.com/config/${distro}/${version_id}/packages-microsoft-prod.deb"
    local tmp
    tmp="$(mktemp -t packages-microsoft-prod.XXXXXX.deb)" || fail "Failed to create temp file"
    # EXIT covers fail()'s exit 1 path; RETURN covers normal returns. Without
    # EXIT, every fail() in this function would leak $tmp under /tmp.
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" EXIT RETURN
    http_get_retry "$deb_url" "$tmp" \
      || fail "Failed to download packages-microsoft-prod.deb from $deb_url"
    sudo dpkg -i "$tmp" || fail "Failed to install packages-microsoft-prod.deb"
    sudo apt update -y || fail "Failed to apt update after adding Microsoft repo"
  fi

  sudo apt install -y powershell || fail "Failed to install powershell via apt"
}

# Install or update pwsh on Arch via yay (AUR: powershell-bin).
# $1 = "true" for --update mode (no --needed, so yay re-fetches).
_setup_pwsh_arch() {
  local update="$1"
  command -v yay >/dev/null 2>&1 || fail "yay required for pwsh on Arch (run setup_yay first)"
  if [[ "$update" == "true" ]]; then
    yay -S --noconfirm powershell-bin || fail "Failed to update powershell-bin via yay"
  else
    yay -S --needed --noconfirm powershell-bin || fail "Failed to install powershell-bin via yay"
  fi
}

# Bootstrap Homebrew on Linux. Idempotent. Sources brew's shellenv so the rest
# of the script run can use `brew` directly. In --update mode, also runs
# `brew update && brew upgrade` for all linuxbrew-managed formulae.
# Usage: setup_brew_linux [--update]
function setup_brew_linux {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} Homebrew (linuxbrew)..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        NONINTERACTIVE=1 /bin/bash -c \
          "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
          || fail "Failed to install Homebrew"
      fi
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ "$update" == "false" ]]; then
      info "Already installed Homebrew"
    fi
    if [[ "$update" == "true" ]]; then
      brew update || fail "Failed to update Homebrew"
      brew upgrade || fail "Failed to upgrade Homebrew packages"
    fi
  fi
  success "Finished Homebrew"
}

# Install or update Claude Code via the official install script. Self-updates
# via `claude update`. Idempotent: no-op if `claude` is on PATH (unless
# --update is passed). Usage: setup_claude_code [--update]
function setup_claude_code {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} Claude Code..."
  if [[ "$DRY" == "false" ]]; then
    if command -v claude >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        claude update || fail "Failed to update Claude Code"
      else
        info "Already installed Claude Code"
      fi
    else
      curl -fsSL https://claude.ai/install.sh | bash \
        || fail "Failed to install Claude Code"
    fi
  fi
  success "Finished Claude Code"
}

# Install or update OpenCode via the official install script. Self-updates
# via `opencode upgrade`. Idempotent: no-op if `opencode` is on PATH (unless
# --update is passed). Usage: setup_opencode [--update]
function setup_opencode {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} OpenCode..."
  if [[ "$DRY" == "false" ]]; then
    if command -v opencode >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        opencode upgrade || fail "Failed to update OpenCode"
      else
        info "Already installed OpenCode"
      fi
    else
      curl -fsSL https://opencode.ai/install | bash \
        || fail "Failed to install OpenCode"
    fi
  fi
  success "Finished OpenCode"
}

DEBIAN_PACKAGES=(
  build-essential libssl-dev zlib1g-dev libbz2-dev
  libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils
  tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
  unzip zsh vim tmux fontconfig fzf fd-find ripgrep nmap
  procps file
)

# Packages installed via linuxbrew on Debian/Ubuntu. Use this list for tools
# that aren't in apt (or are too stale there).
DEBIAN_BREW_PACKAGES=(jj lazygit zoxide)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_pwsh --update
    setup_brew_linux --update
  fi
  success "Finished update for Debian"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_neovim

    setup_fdfind
    setup_pwsh
    setup_brew_linux
    brew install "${DEBIAN_BREW_PACKAGES[@]}" \
      || fail "Failed to install Debian brew packages"
    setup_claude_code
    setup_opencode
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl wget git unzip zsh vim tmux fontconfig
  fzf fd ripgrep lazygit ttf-firacode-nerd zoxide
  gnupg wl-clipboard openssh lua51 luarocks nvm
  tree-sitter-cli nmap jujutsu
)

function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
    setup_pwsh --update
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
    setup_yay
    setup_pwsh
    setup_claude_code
    setup_opencode
  fi
  success "Finished install for Arch Linux"
}

MAC_BREW_PACKAGES=(
  bash wget tmux git vim neovim fzf fd ripgrep gcc font-fira-code-nerd-font
  gnupg pinentry-mac jesseduffield/lazygit/lazygit ast-grep zoxide nmap jj
)
MAC_BREW_CASKS=(ghostty powershell)

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
    setup_claude_code
    setup_opencode
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
