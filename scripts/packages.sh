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

# Map `uname -m` to the arch slug used by lazygit release assets.
_lazygit_arch() {
  case "$(uname -m)" in
    x86_64)        echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) fail "Unsupported arch for lazygit: $(uname -m)" ;;
  esac
}

# Install or update lazygit from its GitHub releases into ~/.local/bin.
# Debian only — Arch installs it via pacman, macOS via brew. Idempotent: in
# install mode, no-op if `lazygit` is already on PATH; --update always fetches
# the latest. Reuses _install_from_github_release (sha256-verified) and
# ensure_jq from languages.sh. Usage: setup_lazygit [--update]
function setup_lazygit {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} lazygit..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v lazygit >/dev/null 2>&1; then
      info "Already installed lazygit"
      success "Finished lazygit"
      return
    fi
    ensure_jq
    local release_json tag
    release_json="$(http_get_retry https://api.github.com/repos/jesseduffield/lazygit/releases/latest)" \
      || fail "Failed to fetch lazygit releases/latest"
    tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
    [[ -n "$tag" ]] || fail "Could not read tag_name from lazygit releases/latest"
    # lazygit asset drops the leading 'v' from the tag (e.g. lazygit_0.44.2_Linux_x86_64.tar.gz).
    local asset="lazygit_${tag#v}_Linux_$(_lazygit_arch).tar.gz"
    _install_from_github_release "lazygit" "lazygit" "$release_json" "$tag" "$asset" "flat-binary" "lazygit"
  fi
  success "Finished lazygit"
}

# Map `uname -m` to the arch slug used by jj (jujutsu) release assets.
_jj_arch() {
  case "$(uname -m)" in
    x86_64)        echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) fail "Unsupported arch for jj: $(uname -m)" ;;
  esac
}

# Install or update jj (jujutsu) from its GitHub releases into ~/.local/bin.
# Debian only — Arch installs it via pacman (jujutsu), macOS via brew (jj).
# Idempotent: in install mode, no-op if `jj` is already on PATH; --update
# always fetches the latest. Usage: setup_jj [--update]
function setup_jj {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} jj..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v jj >/dev/null 2>&1; then
      info "Already installed jj"
      success "Finished jj"
      return
    fi
    ensure_jq
    local release_json tag
    release_json="$(http_get_retry https://api.github.com/repos/jj-vcs/jj/releases/latest)" \
      || fail "Failed to fetch jj releases/latest"
    tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
    [[ -n "$tag" ]] || fail "Could not read tag_name from jj releases/latest"
    # jj asset keeps the leading 'v' (e.g. jj-v0.42.0-x86_64-unknown-linux-musl.tar.gz).
    local asset="jj-${tag}-$(_jj_arch)-unknown-linux-musl.tar.gz"
    _install_from_github_release "jj" "jj" "$release_json" "$tag" "$asset" "flat-binary" "jj"
  fi
  success "Finished jj"
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

# Install or update bun via the official install script. Self-updates via
# `bun upgrade`. Idempotent: no-op if `bun` is on PATH (unless --update is
# passed). Usage: setup_bun [--update]
function setup_bun {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} bun..."
  if [[ "$DRY" == "false" ]]; then
    if command -v bun >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        bun upgrade || fail "Failed to update bun"
      else
        info "Already installed bun"
      fi
    else
      curl -fsSL https://bun.sh/install | bash \
        || fail "Failed to install bun"
      export PATH="$HOME/.bun/bin:$PATH"
    fi
  fi
  success "Finished bun"
}

# Install or update OpenAI Codex CLI via bun's global package manager. Codex
# has no first-party curl installer, so we install the npm package globally
# via bun. Ensures bun is present first. Idempotent: no-op if `codex` is on
# PATH (unless --update is passed). Usage: setup_codex [--update]
function setup_codex {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} Codex..."
  if [[ "$DRY" == "false" ]]; then
    if command -v codex >/dev/null 2>&1 && [[ "$update" == "false" ]]; then
      info "Already installed Codex"
    else
      setup_bun
      if [[ "$update" == "true" ]]; then
        bun update -g @openai/codex || fail "Failed to update Codex"
      else
        bun install -g @openai/codex || fail "Failed to install Codex"
      fi
    fi
  fi
  success "Finished Codex"
}

# build-essential: nvim-treesitter compiles parsers with cc.
# xz-utils: required to extract the Zig .tar.xz in `dotfile languages zig`.
DEBIAN_PACKAGES=(
  build-essential curl git xz-utils
  unzip zsh tmux fontconfig fzf fd-find ripgrep
  procps file zoxide
)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_lazygit --update
    setup_jj --update
    setup_opencode --update
    setup_codex --update
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
    setup_lazygit
    setup_jj
    setup_opencode
    setup_codex
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl wget git unzip zsh tmux fontconfig
  fzf fd ripgrep lazygit ttf-firacode-nerd zoxide
  gnupg wl-clipboard openssh lua51 luarocks nvm
  tree-sitter-cli jujutsu
)

function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
    setup_opencode --update
    setup_codex --update
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
    setup_opencode
    setup_codex
  fi
  success "Finished install for Arch Linux"
}

MAC_BREW_PACKAGES=(
  bash wget tmux git neovim fzf fd ripgrep gcc font-fira-code-nerd-font
  gnupg pinentry-mac jesseduffield/lazygit/lazygit ast-grep zoxide jj
)
MAC_BREW_CASKS=(ghostty)

function update_mac {
  info "Updating packages for Mac..."
  if [[ "$DRY" == "false" ]]; then
    brew update || fail "Failed to update brew"
    brew upgrade || fail "Failed to upgrade brew packages"
    setup_opencode --update
    setup_codex --update
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
    setup_opencode
    setup_codex
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
