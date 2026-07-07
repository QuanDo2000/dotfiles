#!/usr/bin/env bash
set -eo pipefail

DEBIAN_PACKAGES=(
  curl git zsh procps file
)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    _home_manager_switch
  fi
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
  if [[ "$DRY" == "false" ]]; then
    _home_manager_switch
  fi
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
  _ensure_nix
  local target
  target="$(_linux_home_manager_target)"
  if command -v home-manager >/dev/null 2>&1; then
    _run_nix_managed_switch "home-manager switch failed" \
      home-manager switch --flake "$target"
  else
    _run_nix_managed_switch "home-manager bootstrap switch failed" \
      nix run "$DOTFILES_DIR#home-manager" -- switch --flake "$target"
  fi
}

_host_config_value() {
  nix eval --raw --file "$DOTFILES_DIR/config/host.nix" "$1"
}

function _linux_home_manager_target {
  local username
  username="$(_host_config_value username)" \
    || fail "Failed to resolve Linux Home Manager username"
  echo "$DOTFILES_DIR#${username}@linux"
}

function _darwin_flake_target {
  echo "$DOTFILES_DIR#mac"
}

function _nixos_flake_target {
  echo "$DOTFILES_DIR#$(_host_config_value hostName)"
}

function _dry_run_nix_managed_switch {
  info "Would run: $*"
}

function _run_nix_managed_switch {
  local fail_message="$1"
  shift
  "$@" || fail "$fail_message"
}

function _darwin_rebuild_switch {
  _ensure_nix
  local target
  target="$(_darwin_flake_target)"
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
  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo HOME=/var/root darwin-rebuild switch --flake "$(_darwin_flake_target)"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
  fi
  success "Finished update for Mac"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo HOME=/var/root darwin-rebuild switch --flake "$(_darwin_flake_target)"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
  fi
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

  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo nixos-rebuild "${args[@]}" --flake "$target"
  if [[ "$DRY" == "false" ]]; then
    _run_nix_managed_switch "$fail_message" sudo nixos-rebuild "${args[@]}" --flake "$target"
  fi
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

function update_packages {
  info "Updating packages..."
  case "$(detect_platform)" in
    nixos)   update_nixos ;;
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
    nixos)   install_nixos ;;
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  set_zsh_default
  success "Finished install"
}
