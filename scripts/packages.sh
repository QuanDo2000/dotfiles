#!/usr/bin/env bash
set -eo pipefail

if ! declare -F host_config_value >/dev/null; then
  # shellcheck source=scripts/host_config.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host_config.sh"
fi

DEBIAN_PACKAGES=(
  curl git zsh procps file
)

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    _install_native_bootstrap_packages debian
    _home_manager_switch linux
  fi
  success "Finished install for Debian"
}

function _update_flake_inputs {
  if [[ "$DRY" == "true" ]]; then
    _dry_run_nix_managed_switch nix flake update --flake "$DOTFILES_DIR"
    return
  fi

  _ensure_nix
  _run_nix_managed_switch "nix flake update failed" nix flake update --flake "$DOTFILES_DIR"
}

ARCH_PACKAGES=(
  base-devel curl git zsh fuse3 jq openssh ttf-firacode-nerd
)

function _run_system_package_command {
  if [[ "$DRY" == "true" ]]; then
    info "Would run: $*"
  else
    "$@" || fail "System package upgrade failed: $*"
  fi
}

function upgrade_system_packages {
  info "Upgrading native system packages..."
  case "$(detect_platform)" in
    arch)
      _run_system_package_command sudo pacman -Syu
      ;;
    debian)
      _run_system_package_command sudo apt-get update
      _run_system_package_command sudo apt-get upgrade -y
      ;;
    mac)
      _run_system_package_command brew update
      _run_system_package_command brew upgrade --greedy
      ;;
    nixos)
      fail "NixOS packages are managed declaratively; use dotfile update"
      ;;
    unknown)
      fail "Unsupported system: $(uname) (could not detect Linux distro)"
      ;;
  esac
  success "Finished upgrading native system packages"
}

function _install_native_bootstrap_packages {
  local package status installed=true
  case "$1" in
    debian)
      for package in "${DEBIAN_PACKAGES[@]}"; do
        status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" || { installed=false; break; }
        [[ "$status" == "install ok installed" ]] || { installed=false; break; }
      done
      if [[ "$installed" == true ]]; then
        info "Debian bootstrap packages already installed"
      else
        _run_nix_managed_switch "Failed to install Debian packages" \
          sudo apt install -y "${DEBIAN_PACKAGES[@]}"
      fi
      ;;
    arch)
      if command -v pacman >/dev/null 2>&1 \
        && pacman -Q "${ARCH_PACKAGES[@]}" >/dev/null 2>&1; then
        info "Arch bootstrap packages already installed"
      else
        _run_nix_managed_switch "Failed to install Arch packages" \
          sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}"
      fi
      ;;
    nixos|mac) ;;
  esac
}

function _install_arch_service_state_backup {
  local installer="$DOTFILES_DIR/config/arch-server/service-state-backup/install.sh"
  if [[ "$DRY" == "true" ]]; then
    info "Would install Arch server service-state backup units"
    return
  fi
  sudo bash "$installer" || fail "Failed to install Arch server service-state backup units"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    _install_native_bootstrap_packages arch
  fi
  _home_manager_switch arch-server
  _install_arch_service_state_backup
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

# Rolling official binaries stay blocked unless their reviewed hashes match.
LIX_INSTALLER_X86_64_LINUX_SHA256="57564e78a6d57126661fe5e793de70a72bacf9835ddb7c5c0cbfadf3db21545e"
LIX_INSTALLER_AARCH64_DARWIN_SHA256="3c71fdcfeddac8fa075b626b6e0ddd9ba73af930e47b4fa027e22c7279f596ae"
LIX_BOOTSTRAP_VERSION="2.95.2"
LIX_PACKAGE_X86_64_LINUX_SHA256="1f3265d3ef821e723f8c538bca71b537b68553cd7a8cd423e54bdc1185ab5616"
LIX_PACKAGE_AARCH64_DARWIN_SHA256="e913209b741e4633acc8cd16e28c395163b5064f8f3211877baaab42d7372f1d"

function _lix_installer_target {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64) printf 'x86_64-linux\n' ;;
    Darwin:arm64|Darwin:aarch64) printf 'aarch64-darwin\n' ;;
    *) return 1 ;;
  esac
}

function _lix_installer_sha256 {
  case "$1" in
    x86_64-linux) printf '%s\n' "$LIX_INSTALLER_X86_64_LINUX_SHA256" ;;
    aarch64-darwin) printf '%s\n' "$LIX_INSTALLER_AARCH64_DARWIN_SHA256" ;;
    *) return 1 ;;
  esac
}

function _lix_package_sha256 {
  case "$1" in
    x86_64-linux) printf '%s\n' "$LIX_PACKAGE_X86_64_LINUX_SHA256" ;;
    aarch64-darwin) printf '%s\n' "$LIX_PACKAGE_AARCH64_DARWIN_SHA256" ;;
    *) return 1 ;;
  esac
}

function _lix_installer_url {
  printf 'https://install.lix.systems/lix/lix-installer-%s\n' "$1"
}

function _lix_package_url {
  printf 'https://releases.lix.systems/lix/lix-%s/lix-%s-%s.tar.xz\n' \
    "$LIX_BOOTSTRAP_VERSION" "$LIX_BOOTSTRAP_VERSION" "$1"
}

function _download_lix_installer {
  local target="$1" output="$2"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --location --silent --show-error \
    "$(_lix_installer_url "$target")" --output "$output"
}

function _download_lix_package {
  local target="$1" output="$2"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --location --silent --show-error \
    "$(_lix_package_url "$target")" --output "$output"
}

function _file_sha256 {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

function _install_lix {
  local target expected actual package_expected package_actual tmp_dir installer package
  info "Installing Lix/Nix..."
  target="$(_lix_installer_target)" \
    || fail "Unsupported Lix installer platform: $(uname -s) $(uname -m)"
  expected="$(_lix_installer_sha256 "$target")" \
    || fail "Missing Lix installer checksum for $target"
  package_expected="$(_lix_package_sha256 "$target")" \
    || fail "Missing Lix package checksum for $target"
  tmp_dir="$(mktemp -d)" || fail "Failed to create Lix installer temp directory"
  installer="$tmp_dir/lix-installer"
  package="$tmp_dir/lix-package.tar.xz"

  if ! _download_lix_installer "$target" "$installer"; then
    rm -rf "$tmp_dir"
    fail "Failed to download Lix installer"
  fi
  if ! actual="$(_file_sha256 "$installer")"; then
    rm -rf "$tmp_dir"
    fail "Failed to hash Lix installer"
  fi
  if [[ "$actual" != "$expected" ]]; then
    rm -rf "$tmp_dir"
    fail "Lix installer checksum mismatch for $target"
  fi
  if ! _download_lix_package "$target" "$package"; then
    rm -rf "$tmp_dir"
    fail "Failed to download Lix package"
  fi
  if ! package_actual="$(_file_sha256 "$package")"; then
    rm -rf "$tmp_dir"
    fail "Failed to hash Lix package"
  fi
  if [[ "$package_actual" != "$package_expected" ]]; then
    rm -rf "$tmp_dir"
    fail "Lix package checksum mismatch for $target"
  fi
  chmod 0700 "$installer" || { rm -rf "$tmp_dir"; fail "Failed to prepare Lix installer"; }
  if ! "$installer" install --no-confirm --nix-package-url "$package"; then
    rm -rf "$tmp_dir"
    fail "Failed to install Lix/Nix"
  fi
  rm -rf "$tmp_dir"
}

function _ensure_nix {
  _load_nix_profile
  if ! command -v nix >/dev/null 2>&1; then
    _install_lix
    _load_nix_profile
  fi
}

function _refresh_managed_path {
  local dir user_name
  user_name="${USER:-$(id -un)}"
  for dir in \
    /run/current-system/sw/bin \
    "$HOME/.nix-profile/bin" \
    "/etc/profiles/per-user/$user_name/bin" \
    "$HOME/.local/bin"; do
    [[ -d "$dir" && ":$PATH:" != *":$dir:"* ]] && PATH="$dir:$PATH"
  done
  export PATH
}

function _home_manager_switch {
  local profile="${1:-linux}" target
  if [[ "$DRY" == "true" ]]; then
    target="$(_linux_home_manager_target "$profile")"
    _dry_run_nix_managed_switch home-manager switch --flake "$target"
    return
  fi

  _ensure_nix
  target="$(_linux_home_manager_target "$profile")"
  if command -v home-manager >/dev/null 2>&1; then
    _run_nix_managed_switch "home-manager switch failed" \
      home-manager switch --flake "$target"
  else
    _run_nix_managed_switch "home-manager bootstrap switch failed" \
      nix run "$DOTFILES_DIR#home-manager" -- switch --flake "$target"
  fi
}

function _linux_home_manager_target {
  local profile="${1:-linux}" username
  username="$(host_config_value username)" \
    || fail "Failed to resolve Linux Home Manager username"
  echo "${DOTFILE_FLAKE_REF:-$DOTFILES_DIR}#${username}@${profile}"
}

function _nixos_flake_target {
  local host_name
  host_name="$(host_config_value hostName)" \
    || fail "Failed to resolve NixOS host name"
  is_wsl && host_name="${host_name}-wsl"
  echo "${DOTFILE_FLAKE_REF:-$DOTFILES_DIR}#$host_name"
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
  target="${DOTFILE_FLAKE_REF:-$DOTFILES_DIR}#mac"
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
  _refresh_managed_path
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
    elif [[ "${SHELL:-}" == "$zsh_path" || "$(basename "${SHELL:-}")" == "zsh" ]]; then
      info "Already has zsh as default shell"
    else
      chsh -s "$zsh_path"
    fi
  fi
  success "Finished changing zsh as default"
}

function _nixos_rebuild_switch {
  local target configured_user current_user distro
  target="$(_nixos_flake_target)"

  if [[ "$DRY" == "true" ]]; then
    _dry_run_nix_managed_switch sudo nixos-rebuild switch --flake "$target"
    return
  fi

  if is_wsl; then
    configured_user="$(host_config_value username)" \
      || fail "Failed to resolve NixOS username"
    current_user="$(id -un)"
    if [[ "$current_user" != "$configured_user" ]]; then
      _run_nix_managed_switch "nixos-rebuild boot failed" sudo nixos-rebuild boot --flake "$target"
      NIXOS_WSL_RESTART_REQUIRED=true
      distro="${WSL_DISTRO_NAME:-NixOS}"
      info "NixOS-WSL user change to $configured_user is staged; user tools were not synced"
      info "Exit WSL, then run in PowerShell: wsl -t $distro; wsl -d $distro --user root exit; wsl -t $distro"
      info "Reopen WSL, move this checkout to /home/$configured_user/dotfiles, and rerun dotfile packages"
      return
    fi
  fi

  _run_nix_managed_switch "nixos-rebuild switch failed" sudo nixos-rebuild switch --flake "$target"

  if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null
  fi
}

# Reprovision NixOS from this repo's flake. System packages come from the
# rebuild; user config and Codex skills come from Home Manager.
# Usage: install_nixos
function install_nixos {
  info "Installing packages for NixOS..."
  _nixos_rebuild_switch
  [[ "${NIXOS_WSL_RESTART_REQUIRED:-false}" == "true" ]] && return
  success "Finished install for NixOS"
}

function _sync_neovim {
  NEOVIM_SYNC_ERROR=
  if [ "$DRY" = true ]; then
    info "Would restore Neovim plugins and tools"
    return
  fi

  info "Restoring Neovim plugins and tools..."
  local output

  if output="$(DOTFILE_NVIM_SYNC=0 nvim --headless "+lua if require('config.sync').runtime_complete() then print('RAW_NEOVIM_SYNC_CURRENT') end" +qa 2>&1)" \
    && [[ "$output" == *RAW_NEOVIM_SYNC_CURRENT* ]]; then
    info "Neovim plugins and tools already current"
    return
  fi

  if ! output="$(DOTFILE_NVIM_SYNC=1 nvim --headless "+lua local sync = require('config.sync'); sync.plugins(true); sync.tools(); sync.parsers(); print('RAW_NEOVIM_SYNC_OK')" +qa 2>&1)"; then
    NEOVIM_SYNC_ERROR="Neovim plugin or tool sync failed:\n$output"
    return 1
  fi
  if [[ "$output" != *RAW_NEOVIM_SYNC_OK* ]]; then
    NEOVIM_SYNC_ERROR="Neovim plugin or tool sync did not complete:\n$output"
    return 1
  fi
}

function _update_pi_extensions {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Pi extensions"
  else
    pi update --extensions || fail "Failed to update Pi extensions"
  fi
}

function _update_packages_scope {
  local scope="$1" platform codex_version_before refresh marker label suffix pending_args=()
  if [[ "$scope" == ai ]]; then
    refresh=_refresh_ai_dependency_set marker=ai label="AI dependency" suffix="AI update" pending_args=(ai)
    info "Updating AI tools and configs..."
  else
    refresh=_refresh_all_dependency_set marker=full label=Dependency suffix=update
    info "Updating packages..."
  fi
  codex_version_before="$(_codex_version)"
  platform="$(detect_platform)"
  case "$platform" in
    nixos|debian|arch|mac) ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  [[ "$DRY" == "true" ]] || _begin_dependency_update \
    || fail "Another dependency update is already running"

  if [[ "$DRY" == "true" ]]; then
    "$refresh"
    _validate_dependency_update
  elif _dependency_update_markers_conflict; then
    fail "Conflicting pending dependency updates require manual review"
  elif _dependency_update_pending "${pending_args[@]}"; then
    _validate_pending_dependency_update "${pending_args[@]}"
    info "Resuming validated $label update"
  else
    _require_clean_dependency_tree
    _refresh_dependency_set "$refresh" \
      || fail "$label refresh failed; working tree was not changed"
    _write_dependency_update_marker "$marker" "$DEPENDENCY_UPDATE_FINGERPRINT" \
      || fail "Failed to record validated $label update"
  fi
  _approve_dependency_update
  [[ "$DRY" == "true" ]] || _validate_pending_dependency_update "${pending_args[@]}"
  if [[ "$scope" != ai && "$DRY" == "false" ]]; then
    _install_native_bootstrap_packages "$platform"
  fi
  case "$platform" in
    nixos)   DOTFILE_FLAKE_REF="path:$DOTFILES_DIR" _nixos_rebuild_switch ;;
    debian)  DOTFILE_FLAKE_REF="path:$DOTFILES_DIR" _home_manager_switch linux ;;
    arch)    DOTFILE_FLAKE_REF="path:$DOTFILES_DIR" _home_manager_switch arch-server ;;
    mac)     DOTFILE_FLAKE_REF="path:$DOTFILES_DIR" _darwin_rebuild_switch ;;
  esac
  if [[ "$platform" == arch && "$scope" != ai ]]; then
    _install_arch_service_state_backup
  fi
  _cleanup_codex_runtime_after_update "$codex_version_before"
  _update_pi_extensions
  local neovim_sync_error=
  [[ "$scope" == ai ]] || _sync_neovim || neovim_sync_error="$NEOVIM_SYNC_ERROR"
  [ -z "$neovim_sync_error" ] || fail "$neovim_sync_error"
  _publish_dependency_update "$scope"
  _finish_dependency_update "${pending_args[@]}"
  [[ "$DRY" == "true" ]] || _end_dependency_update \
    || fail "Failed to release dependency update lock"
  success "Finished $suffix"
}

function update_ai { _update_packages_scope ai; }

function update_packages { _update_packages_scope full; }

function install_packages {
  info "Installing packages..."
  case "$(detect_platform)" in
    nixos)   install_nixos ;;
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  [[ "${NIXOS_WSL_RESTART_REQUIRED:-false}" == "true" ]] && return
  set_zsh_default
  _sync_neovim || fail "$NEOVIM_SYNC_ERROR"
  success "Finished install"
}
