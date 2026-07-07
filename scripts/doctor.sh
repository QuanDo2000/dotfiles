#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"
scripts_dir="${SCRIPTS_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
source "$scripts_dir/obsidian_paths.sh"

# Core symlinked dotfiles under $HOME. This is a smoke check, not a full package audit.
HM_MANAGED_PATHS_FILE="${HM_MANAGED_PATHS_FILE:-$DOTFILES_DIR/config/home-manager-managed-paths}"
if [[ ! -f "$HM_MANAGED_PATHS_FILE" && -f "$scripts_dir/../config/home-manager-managed-paths" ]]; then
  HM_MANAGED_PATHS_FILE="$scripts_dir/../config/home-manager-managed-paths"
fi

_read_home_manager_managed_paths() {
  local callback="$1" kind path
  [[ -f "$HM_MANAGED_PATHS_FILE" ]] || return 0
  while read -r kind path; do
    [[ -n "${kind:-}" && "${kind:0:1}" != "#" ]] || continue
    "$callback" "$kind" "$path"
  done < "$HM_MANAGED_PATHS_FILE"
}

_collect_required_symlink() {
  local kind="$1" path="$2"
  case "$kind $path" in
    "home .zshrc"|"home .zshrc.base"|"home .tmux.conf"|"home .vimrc"|"home .gitconfig"|"home .zprofile")
      REQUIRED_SYMLINKS+=("$path")
      ;;
  esac
}

REQUIRED_SYMLINKS=()
_read_home_manager_managed_paths _collect_required_symlink

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

_doctor_check_managed_paths() {
  if [[ ! -f "$HM_MANAGED_PATHS_FILE" ]]; then
    fail_soft "Home Manager managed path manifest not found: $HM_MANAGED_PATHS_FILE"
    errors=$((errors + 1))
    return
  fi

  _read_home_manager_managed_paths _doctor_check_managed_path_entry
}

_doctor_check_managed_path_entry() {
  local kind="$1" path="$2"
  case "$kind" in
    home) _doctor_check_managed_path "$path" "$HOME/$path" ;;
    config) _doctor_check_managed_path ".config/$path" "${XDG_CONFIG_HOME:-$HOME/.config}/$path" ;;
    data) _doctor_check_managed_path ".local/share/$path" "${XDG_DATA_HOME:-$HOME/.local/share}/$path" ;;
    *)
      fail_soft "Unknown Home Manager managed path kind '$kind' in $HM_MANAGED_PATHS_FILE"
      errors=$((errors + 1))
      ;;
  esac
}

_check_obsidian_config() {
  local tracked_dir="$OBSIDIAN_CONFIG_SOURCE"
  local live_dir="$OBSIDIAN_CONFIG_VAULT"

  [ -d "$tracked_dir" ] || {
    info "Skipping Obsidian config drift check: $tracked_dir not found"
    return 0
  }
  [ -d "$live_dir" ] || {
    info "Skipping Obsidian config drift check: $live_dir not found"
    return 0
  }

  local tracked relative live obsidian_errors=0
  while IFS= read -r tracked; do
    relative="${tracked#"$tracked_dir"/}"
    live="$live_dir/$relative"
    if [[ ! -f "$live" ]]; then
      fail_soft "Obsidian config missing: $relative"
      errors=$((errors + 1))
      obsidian_errors=$((obsidian_errors + 1))
    elif ! cmp -s "$tracked" "$live"; then
      fail_soft "Obsidian config drift: $relative"
      errors=$((errors + 1))
      obsidian_errors=$((obsidian_errors + 1))
    fi
  done < <(find "$tracked_dir" -type f | sort)

  if [[ "$obsidian_errors" -eq 0 ]]; then
    success "Obsidian config matches tracked settings"
  else
    info "Run 'dotfile -f obsidian-config' to apply tracked Obsidian config" --force
  fi
}

function doctor {
  local errors=0
  local platform
  platform="$(detect_platform)"

  info "Checking Home Manager-managed paths..."
  if is_home_manager_platform "$platform"; then
    _doctor_check_managed_paths
    if [[ "$platform" == "mac" ]]; then
      _doctor_check_managed_path ".zshrc.mac" "$HOME/.zshrc.mac"
      _doctor_check_managed_path ".local/bin/caf" "$HOME/.local/bin/caf"
    else
      _doctor_check_managed_path ".local/bin/dotfile" "$HOME/.local/bin/dotfile"
    fi
    success "Home Manager-managed paths are clear"
  else
    info "Skipping Home Manager conflict checks on $platform"
  fi

  info "Verifying symlinks..."
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    _check_symlink "$f" "$platform"
  done
  _check_dotfile_command
  _check_nix_tool codex "$platform"
  _check_nix_tool codebase-memory-mcp "$platform"
  _check_obsidian_config
  _check_nix_config "$platform"

  echo ""
  if [ "$errors" -eq 0 ]; then
    success "All checks passed!" --force
    return 0
  fi

  info "$errors issue(s) found" --force
  return 1
}
