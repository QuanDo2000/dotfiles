#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Core symlinked dotfiles under $HOME. This is a smoke check, not a full package audit.
REQUIRED_SYMLINKS=(.zshrc .zshrc.base .tmux.conf .vimrc .gitconfig .zprofile)
HM_HOME_PATHS=(
  .gitconfig
  .vimrc
  .tmux.conf
  .zprofile
  .zshrc.base
  .zshrc
  .ssh/config
  .claude/settings.json
  .tmux/plugins/tmux-yank
  .tmux/plugins/catppuccin/tmux
)
HM_CONFIG_PATHS=(
  starship.toml
  jj
  nvim
  fcitx5
  ghostty/config
  hypr
  waybar
)
HM_DATA_PATHS=(
  zsh/plugins/zsh-autosuggestions
  zsh/plugins/fast-syntax-highlighting
  zsh/plugins/fzf-tab
)

# Helper: check that a file is a symlink pointing into DOTFILES_DIR.
_check_symlink() {
  local name="$1"
  local target="$HOME/$name"
  local platform="${2:-$(detect_platform)}"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(resolve_symlink "$target")"
    if [[ "$link_target" == "$DOTFILES_DIR"* ]] \
      || { is_home_manager_platform "$platform" && [[ "$link_target" == /nix/store/* ]]; }; then
      success "$name -> $link_target"
    else
      fail_soft "$name points to $link_target (expected $DOTFILES_DIR/... or Home Manager store target)"
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

_check_dotfile_command() {
  local target="$HOME/.local/bin/dotfile"
  if [ -L "$target" ]; then
    local link_target platform
    link_target="$(resolve_symlink "$target")"
    platform="$(detect_platform)"
    if [[ "$link_target" == "$DOTFILES_DIR/dotfile" ]] \
      || { is_home_manager_platform "$platform" && [[ "$link_target" == /nix/store/* ]]; }; then
      success ".local/bin/dotfile -> $link_target"
    else
      fail_soft ".local/bin/dotfile points to $link_target (expected $DOTFILES_DIR/dotfile or Home Manager store target)"
      errors=$((errors + 1))
    fi
  elif [ -e "$target" ]; then
    fail_soft ".local/bin/dotfile exists but is not a symlink"
    errors=$((errors + 1))
  else
    fail_soft ".local/bin/dotfile not found"
    errors=$((errors + 1))
  fi
}

_check_nix_tool() {
  local name="$1"
  local platform="${2:-$(detect_platform)}"
  is_home_manager_platform "$platform" || return 0

  local target
  if ! target="$(command -v "$name" 2>/dev/null)"; then
    fail_soft "$name not found (expected /nix/store/...)"
    errors=$((errors + 1))
    return
  fi

  local link_target="$target"
  if [ -L "$target" ]; then
    link_target="$(resolve_symlink "$target")"
  fi

  if [[ "$link_target" == /nix/store/* ]]; then
    success "$name -> $link_target"
  else
    fail_soft "$name points to $link_target (expected /nix/store/...)"
    errors=$((errors + 1))
  fi
}

_doctor_check_managed_path() {
  local label="$1"
  local target="$2"

  [ -e "$target" ] || [ -L "$target" ] || return 0

  if [ -L "$target" ]; then
    local link_target
    link_target="$(resolve_symlink "$target")"
    if [[ "$link_target" == /nix/store/* || "$link_target" == "$DOTFILES_DIR"* ]]; then
      return 0
    fi
  fi

  fail_soft "$label exists but is not Home Manager-owned"
  errors=$((errors + 1))
}

function doctor {
  local errors=0
  local platform
  platform="$(detect_platform)"

  info "Checking Home Manager-managed paths..."
  if ! is_home_manager_platform "$platform"; then
    info "Skipping Home Manager conflict checks on $platform"
    return 0
  fi

  local name
  for name in "${HM_HOME_PATHS[@]}"; do
    _doctor_check_managed_path "$name" "$HOME/$name"
  done
  for name in "${HM_CONFIG_PATHS[@]}"; do
    _doctor_check_managed_path ".config/$name" "${XDG_CONFIG_HOME:-$HOME/.config}/$name"
  done
  for name in "${HM_DATA_PATHS[@]}"; do
    _doctor_check_managed_path ".local/share/$name" "${XDG_DATA_HOME:-$HOME/.local/share}/$name"
  done

  if [[ "$platform" == "mac" ]]; then
    _doctor_check_managed_path ".zshrc.mac" "$HOME/.zshrc.mac"
    _doctor_check_managed_path ".local/bin/caf" "$HOME/.local/bin/caf"
  else
    _doctor_check_managed_path ".local/bin/dotfile" "$HOME/.local/bin/dotfile"
  fi

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "No Home Manager conflicts found" --force
    return 0
  fi

  info "$errors Home Manager conflict(s) found" --force
  return 1
}

function verify {
  local errors=0

  info "Verifying symlinks..."
  local platform
  platform="$(detect_platform)"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    _check_symlink "$f" "$platform"
  done
  _check_dotfile_command
  _check_nix_tool codex "$platform"
  _check_nix_tool codebase-memory-mcp "$platform"

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
    return 0
  else
    info "$errors issue(s) found" --force
    return 1
  fi
}
