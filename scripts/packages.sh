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

function _latest_codex_release_tag {
  local release_url tag
  release_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/openai/codex/releases/latest)" \
    || fail "Failed to check latest Codex release"
  tag="${release_url##*/}"
  [[ "$tag" == rust-v* ]] || fail "Unexpected Codex release tag: $tag"
  printf '%s\n' "$tag"
}

function _codex_release_archive_url {
  printf 'https://github.com/openai/codex/releases/download/%s/codex-package-x86_64-unknown-linux-musl.tar.gz\n' "$1"
}

function _prefetch_codex_release_hash {
  local tag url output hash
  tag="$1"
  url="$(_codex_release_archive_url "$tag")"
  output="$(nix store prefetch-file --json --hash-type sha256 "$url")" \
    || fail "Failed to prefetch Codex release archive"
  hash="$(printf '%s\n' "$output" | sed -n 's/.*"hash":"\([^"]*\)".*/\1/p')"
  [[ -n "$hash" ]] || fail "Failed to parse Codex release archive hash"
  printf '%s\n' "$hash"
}

function _write_codex_release_package {
  local tag hash version package_file tmp
  tag="$1"
  hash="$2"
  version="${tag#rust-v}"
  package_file="$DOTFILES_DIR/packages/codex-release.nix"
  [[ -f "$package_file" ]] || fail "Missing Codex package file: $package_file"

  tmp="$(mktemp)" || fail "Failed to create temp file"
  sed -E \
    -e 's#version = "[^"]+";#version = "'"$version"'";#' \
    -e 's#hash = "[^"]+";#hash = "'"$hash"'";#' \
    "$package_file" > "$tmp" \
    && mv "$tmp" "$package_file" \
    || fail "Failed to update Codex package file"
}

function _update_codex_release_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Codex package from the latest GitHub release"
    return
  fi

  local tag hash version package_file current_version
  package_file="$DOTFILES_DIR/packages/codex-release.nix"
  [[ -f "$package_file" ]] || fail "Missing Codex package file: $package_file"
  tag="$(_latest_codex_release_tag)"
  version="${tag#rust-v}"
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Codex package already at $tag"
    return
  fi

  info "Updating Codex package to $tag..."
  _ensure_nix
  hash="$(_prefetch_codex_release_hash "$tag")"
  _write_codex_release_package "$tag" "$hash"
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

function update_packages {
  info "Updating packages..."
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    nixos|debian|arch|mac) ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  _update_codex_release_package
  case "$platform" in
    nixos)   update_nixos ;;
    debian)  update_debian ;;
    arch)    update_arch ;;
    mac)     update_mac ;;
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
