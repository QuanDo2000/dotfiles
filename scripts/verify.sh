#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Core symlinked dotfiles under $HOME. This is a smoke check, not a full package audit.
REQUIRED_SYMLINKS=(.zshrc.base .tmux.conf .vimrc .gitconfig .zprofile)

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

_check_local_zshrc() {
  local target="$HOME/.zshrc"
  if [ ! -f "$target" ]; then
    fail_soft ".zshrc not found"
    errors=$((errors + 1))
  elif [ -L "$target" ]; then
    fail_soft ".zshrc is a symlink (expected machine-local file)"
    errors=$((errors + 1))
  elif grep -F 'source "$HOME/.zshrc.base"' "$target" >/dev/null 2>&1; then
    success ".zshrc sources ~/.zshrc.base"
  else
    fail_soft ".zshrc does not source ~/.zshrc.base"
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

function verify {
  local errors=0

  info "Verifying symlinks..."
  local platform
  platform="$(detect_platform)"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    _check_symlink "$f" "$platform"
  done
  _check_local_zshrc
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
