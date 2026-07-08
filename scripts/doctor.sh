#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

# Helper: check that a file is a symlink pointing into DOTFILES_DIR.
_check_symlink() {
  local name="$1"
  local target="$HOME/$name"
  local platform="${2:-$(detect_platform)}"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(resolve_symlink "$target")"
    if [[ "$link_target" == "$DOTFILES_DIR/"* ]] \
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
  local platform="${1:-$(detect_platform)}"
  local target="$HOME/.local/bin/dotfile"
  if [ -L "$target" ]; then
    local link_target
    link_target="$(resolve_symlink "$target")"
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

_check_nix_eval() {
  local label="$1"
  local target="$2"
  local output

  if output="$(nix eval --raw "$target" 2>&1 >/dev/null)"; then
    success "$label evaluates"
  else
    if [[ "$output" == *"fetcher-cache-v4.sqlite"* ]]; then
      local cache_dir
      cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfile-nix-cache.XXXXXX")"
      if output="$(XDG_CACHE_HOME="$cache_dir" nix eval --raw "$target" 2>&1 >/dev/null)"; then
        rm -rf "$cache_dir"
        success "$label evaluates"
        return
      fi
      rm -rf "$cache_dir"
    fi

    output="${output//$'\n'/ }"
    if [[ -n "$output" ]]; then
      fail_soft "$label failed to evaluate: $output"
    else
      fail_soft "$label failed to evaluate"
    fi
    errors=$((errors + 1))
  fi
}

_check_nix_config() {
  local platform="$1"
  is_home_manager_platform "$platform" || return 0

  if [[ "${DOTFILE_DOCTOR_SKIP_NIX_EVAL:-false}" == "true" ]]; then
    info "Skipping Nix evaluation: DOTFILE_DOCTOR_SKIP_NIX_EVAL=true"
    return 0
  fi
  if [[ "$DRY" == "true" ]]; then
    info "Skipping Nix evaluation in dry-run mode"
    return 0
  fi
  if ! command -v nix >/dev/null 2>&1; then
    info "Skipping Nix evaluation: nix not found"
    return 0
  fi
  if [[ ! -f "$DOTFILES_DIR/flake.nix" ]]; then
    info "Skipping Nix evaluation: flake.nix not found"
    return 0
  fi

  local username host_name
  username="$(nix eval --raw --file "$DOTFILES_DIR/config/host.nix" username 2>/dev/null || true)"
  host_name="$(nix eval --raw --file "$DOTFILES_DIR/config/host.nix" hostName 2>/dev/null || true)"

  case "$platform" in
    nixos)
      if [[ -z "$host_name" ]]; then
        fail_soft "NixOS hostName failed to evaluate"
        errors=$((errors + 1))
        return
      fi
      _check_nix_eval "NixOS configuration $host_name" "$DOTFILES_DIR#nixosConfigurations.$host_name.config.system.build.toplevel.drvPath"
      ;;
    mac)
      _check_nix_eval "nix-darwin configuration mac" "$DOTFILES_DIR#darwinConfigurations.mac.config.system.build.toplevel.drvPath"
      ;;
    arch | debian)
      if [[ -z "$username" ]]; then
        fail_soft "Home Manager username failed to evaluate"
        errors=$((errors + 1))
        return
      fi
      _check_nix_eval "Home Manager configuration $username@linux" "$DOTFILES_DIR#homeConfigurations.\"$username@linux\".activationPackage.drvPath"
      ;;
  esac
}

function doctor {
  local errors=0
  local platform
  platform="$(detect_platform)"

  info "Verifying symlinks..."
  _check_symlink .zshrc "$platform"
  _check_dotfile_command "$platform"
  _check_nix_config "$platform"

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
    return 0
  fi

  info "$errors issue(s) found" --force
  return 1
}
