#!/usr/bin/env bash
set -eo pipefail

if ! declare -F host_config_value >/dev/null; then
  # shellcheck source=scripts/host_config.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host_config.sh"
fi

DEBIAN_PACKAGES=(
  curl git zsh procps file
)

function update_debian {
  info "Updating packages for Debian..."
  _home_manager_switch
  success "Finished update for Debian"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    _run_nix_managed_switch "Failed to install Debian packages" \
      sudo apt install -y "${DEBIAN_PACKAGES[@]}"
    _home_manager_switch
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl git zsh
)

function update_arch {
  info "Updating packages for Arch Linux..."
  _home_manager_switch
  success "Finished update for Arch Linux"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    _run_nix_managed_switch "Failed to install Arch packages" \
      sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}"
    _home_manager_switch
  fi
  success "Finished install for Arch Linux"
}

function _load_nix_profile {
  local profile status
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    /nix/var/nix/profiles/default/etc/profile.d/nix.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    # shellcheck disable=SC1090
    if [[ -f "$profile" ]]; then
      status=0
      case $- in
        *u*)
          set +u
          source "$profile" || status=$?
          set -u
          ;;
        *)
          source "$profile" || status=$?
          ;;
      esac
      (( status == 0 )) || return "$status"
    fi
  done
}

function _install_lix {
  info "Installing Lix/Nix..."
  curl -sSf -L https://install.lix.systems/lix | sh -s -- install \
    || fail "Failed to install Lix/Nix"
}

function _ensure_nix {
  _load_nix_profile
  if ! command -v nix >/dev/null 2>&1; then
    _install_lix
    _load_nix_profile
  fi
}

function _home_manager_switch {
  local target
  if [[ "$DRY" == "true" ]]; then
    target="$(_linux_home_manager_target)"
    _dry_run_nix_managed_switch home-manager switch --flake "$target"
    return
  fi

  _ensure_nix
  target="$(_linux_home_manager_target)"
  if command -v home-manager >/dev/null 2>&1; then
    _run_nix_managed_switch "home-manager switch failed" \
      home-manager switch --flake "$target"
  else
    _run_nix_managed_switch "home-manager bootstrap switch failed" \
      nix run "$DOTFILES_DIR#home-manager" -- switch --flake "$target"
  fi
}

function _linux_home_manager_target {
  local username
  username="$(host_config_value username)" \
    || fail "Failed to resolve Linux Home Manager username"
  echo "$DOTFILES_DIR#${username}@linux"
}

function _darwin_flake_target {
  echo "$DOTFILES_DIR#mac"
}

function _nixos_flake_target {
  local host_name
  host_name="$(host_config_value hostName)" \
    || fail "Failed to resolve NixOS host name"
  echo "$DOTFILES_DIR#$host_name"
}

function _dry_run_nix_managed_switch {
  info "Would run: $*"
}

function _run_nix_managed_switch {
  local fail_message="$1"
  shift
  "$@" || fail "$fail_message"
}

function _codex_version {
  command -v codex >/dev/null 2>&1 || return 0
  codex --version 2>/dev/null || true
}

function _codex_version_number {
  printf '%s\n' "$1" | sed -n 's/.* \([0-9][^[:space:]]*\)$/\1/p'
}

function _codex_model_cache_version {
  local codex_home cache_file
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  cache_file="$codex_home/models_cache.json"
  [[ -f "$cache_file" ]] || return 0
  jq -r '.client_version // empty' "$cache_file" 2>/dev/null || true
}

function _cleanup_stale_codex_runtime {
  local codex_home
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  codex app-server daemon stop >/dev/null 2>&1 || true
  rm -f "$codex_home/models_cache.json" "$codex_home/app-server-control/app-server-control.sock"
}

function _cleanup_codex_runtime_after_update {
  local before after after_number cache_version reason
  [[ "$DRY" == "true" ]] && return 0
  before="$1"
  reason=""
  after="$(_codex_version)"
  if [[ -n "$before" && -n "$after" && "$before" != "$after" ]]; then
    reason="Codex version changed"
  else
    after_number="$(_codex_version_number "$after" || true)"
    cache_version="$(_codex_model_cache_version || true)"
    if [[ -n "$after_number" && -n "$cache_version" && "$after_number" != "$cache_version" ]]; then
      reason="Codex model cache is stale"
    fi
  fi

  if [[ -n "$reason" ]]; then
    info "$reason; clearing stale runtime cache..."
    _cleanup_stale_codex_runtime
    info "Restart any open Codex sessions to use the new version"
  fi
  return 0
}

function _darwin_rebuild_switch {
  local target
  target="$(_darwin_flake_target)"
  if [[ "$DRY" == "true" ]]; then
    _dry_run_nix_managed_switch sudo HOME=/var/root darwin-rebuild switch --flake "$target"
    return
  fi

  _ensure_nix
  if command -v darwin-rebuild >/dev/null 2>&1; then
    _run_nix_managed_switch "darwin-rebuild switch failed" \
      sudo HOME=/var/root darwin-rebuild switch --flake "$target"
  else
    _run_nix_managed_switch "nix-darwin bootstrap switch failed" \
      sudo HOME=/var/root nix run "$DOTFILES_DIR#darwin-rebuild" -- switch --flake "$target"
  fi
}

function update_mac {
  info "Updating packages for Mac..."
  _darwin_rebuild_switch
  success "Finished update for Mac"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  _darwin_rebuild_switch
  success "Finished install for Mac"
}

function set_zsh_default {
  info "Changing default shell to zsh..."
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    nixos|mac)
      info "Shell is managed declaratively on $platform; skipping chsh"
      success "Finished changing zsh as default"
      return
      ;;
  esac
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

function _nixos_rebuild_switch {
  local upgrade="${1:-false}"
  local target
  target="$(_nixos_flake_target)"
  local args=(switch)
  local fail_message="nixos-rebuild switch failed"

  if [[ "$upgrade" == "true" ]]; then
    args+=(--upgrade)
    fail_message="nixos-rebuild switch --upgrade failed"
  fi

  if [[ "$DRY" == "true" ]]; then
    _dry_run_nix_managed_switch sudo nixos-rebuild "${args[@]}" --flake "$target"
    return
  fi

  _run_nix_managed_switch "$fail_message" sudo nixos-rebuild "${args[@]}" --flake "$target"
}

# Reprovision NixOS from this repo's flake. System packages come from the
# rebuild; user config and Codex skills come from Home Manager.
# Usage: install_nixos
function install_nixos {
  info "Installing packages for NixOS..."
  _nixos_rebuild_switch
  success "Finished install for NixOS"
}

# Update NixOS by rebuilding this repo's flake with channel upgrade.
# Usage: update_nixos
function update_nixos {
  info "Updating packages for NixOS..."
  _nixos_rebuild_switch true
  success "Finished update for NixOS"
}

function _sync_fff_nvim {
  FFF_NVIM_WARNING=
  if [ "$DRY" = true ]; then
    info "Would install or update fff.nvim"
    return
  fi

  info "Installing or updating fff.nvim..."
  local output plugin="$HOME/.local/share/nvim/lazy/fff.nvim"
  local release="$plugin/target/release"
  if ! output="$(nvim --headless "+Lazy! sync fff.nvim" +qa 2>&1)"; then
    FFF_NVIM_WARNING="Lazy sync failed:\n$output"
    return
  fi
  if [ ! -d "$plugin" ]; then
    FFF_NVIM_WARNING="Lazy sync did not install $plugin"
    return
  fi
  if ! output="$(cd "$plugin" && nix run .#release 2>&1)"; then
    FFF_NVIM_WARNING="Nix backend build failed:\n$output"
    return
  fi
  if [ ! -f "$release/libfff_nvim.so" ] && [ ! -f "$release/fff_nvim.so" ] && [ ! -f "$release/libfff_nvim.dylib" ]; then
    FFF_NVIM_WARNING="Nix build completed without an fff.nvim backend in $release"
  fi
}

function _report_fff_nvim_warning {
  [ -z "${FFF_NVIM_WARNING:-}" ] || warn "fff.nvim setup failed; Neovim may start without FFF.\n$FFF_NVIM_WARNING"
}

function update_packages {
  info "Updating packages..."
  local platform codex_version_before
  codex_version_before="$(_codex_version)"
  platform="$(detect_platform)"
  case "$platform" in
    nixos|debian|arch|mac) ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  case "$platform" in
    nixos)   update_nixos ;;
    debian)  update_debian ;;
    arch)    update_arch ;;
    mac)     update_mac ;;
  esac
  _cleanup_codex_runtime_after_update "$codex_version_before"
  _sync_fff_nvim
  success "Finished update"
  _report_fff_nvim_warning
}

function update_codex_release {
  info "Updating pinned Codex release package..."
  _update_codex_release_package
  success "Finished updating pinned Codex release package"
}

function update_obsidian_headless_release {
  info "Updating pinned Obsidian Headless package..."
  _update_obsidian_headless_package
  success "Finished updating pinned Obsidian Headless package"
}

function install_packages {
  info "Installing packages..."
  case "$(detect_platform)" in
    nixos)   install_nixos ;;
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  set_zsh_default
  _sync_fff_nvim
  success "Finished install"
  _report_fff_nvim_warning
}
