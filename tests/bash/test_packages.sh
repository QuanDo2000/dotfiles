#!/usr/bin/env bash
# Tests for individual package installation functions.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh
}

teardown() {
  cleanup_test_env
}

nix() {
  if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "username" ]]; then
    printf 'testuser@linux\n'
    return 0
  fi
  if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "hostName" ]]; then
    printf 'testhost\n'
    return 0
  fi
  printf 'nix %s\n' "$*" >> "$calls"
}

# ---------------------------------------------------------------------------
# Linux package flows
# ---------------------------------------------------------------------------

test_arch_packages_are_bootstrap_only() {
  assert_contains "${ARCH_PACKAGES[*]}" "base-devel"
  assert_contains "${ARCH_PACKAGES[*]}" "curl"
  assert_contains "${ARCH_PACKAGES[*]}" "git"
  assert_contains "${ARCH_PACKAGES[*]}" "zsh"
  for pkg in neovim starship nodejs tmux lazygit jujutsu ripgrep fd fzf; do
    if [[ " ${ARCH_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Arch pacman packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_install_arch_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }

  install_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -S --needed --noconfirm"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "home-manager/master"

  unset -f command sudo _install_lix _load_nix_profile
}

test_update_arch_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -Syu --noconfirm"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_debian_packages_are_bootstrap_only() {
  for pkg in curl git zsh procps file; do
    assert_contains "${DEBIAN_PACKAGES[*]}" "$pkg"
  done
  for pkg in build-essential xz-utils neovim starship nodejs tmux lazygit jujutsu ripgrep fd-find fzf fontconfig zoxide unzip; do
    if [[ " ${DEBIAN_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Debian apt packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_install_debian_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }

  install_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt install -y"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "neovim"

  unset -f command sudo _install_lix _load_nix_profile
}

test_update_debian_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt update -y"
  assert_contains "$output" "sudo apt upgrade -y"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_linux_bootstrap_flows_share_home_manager_helper() {
  local packages_text
  packages_text="$(<"$REPO_DIR/scripts/packages.sh")"

  assert_contains "$packages_text" "function _run_linux_home_manager_bootstrap"
  assert_contains "$packages_text" "_run_linux_home_manager_bootstrap \"Failed to update apt\""
  assert_contains "$packages_text" "_run_linux_home_manager_bootstrap \"Failed to install Debian packages\""
  assert_contains "$packages_text" "_run_linux_home_manager_bootstrap \"Failed to update pacman\""
  assert_contains "$packages_text" "_run_linux_home_manager_bootstrap \"Failed to install Arch packages\""
}

test_packages_do_not_keep_local_release_installer_helpers() {
  local packages_text
  packages_text="$(<"$REPO_DIR/scripts/packages.sh")"

  for helper in _action_verb _install_from_github_release _install_into_local _assert_single_top_dir _strip_sha256_prefix _sha256 ensure_pkg ensure_jq; do
    assert_not_contains "$packages_text" "$helper"
  done
}

# ---------------------------------------------------------------------------
# NixOS package flow
# ---------------------------------------------------------------------------

test_install_nixos_dry_run() {
  DRY=true

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "neovim"
}

test_update_nixos_dry_run() {
  DRY=true

  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#testhost"
}

test_install_nixos_uses_flake_switch() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  install_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--impure"

  unset -f sudo
}

test_update_nixos_uses_flake_switch_upgrade() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  update_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--impure"

  unset -f sudo
}

test_nixos_rebuilds_share_host_target_helper() {
  local packages_text
  packages_text="$(<"$REPO_DIR/scripts/packages.sh")"

  assert_contains "$packages_text" "function _nixos_rebuild_switch"
  assert_contains "$packages_text" "_nixos_rebuild_switch"
  assert_contains "$packages_text" "function _nixos_flake_target"
  assert_contains "$packages_text" "function _run_nix_managed_switch"
}

test_nix_managed_switches_share_runner() {
  local packages_text
  packages_text="$(<"$REPO_DIR/scripts/packages.sh")"

  assert_contains "$packages_text" "function _run_nix_managed_switch"
  assert_not_contains "$packages_text" "_cleanup_home_manager_migration_conflicts"
  assert_contains "$packages_text" "_run_nix_managed_switch \"home-manager switch failed\""
  assert_contains "$packages_text" "_run_nix_managed_switch \"darwin-rebuild switch failed\""
  assert_contains "$packages_text" '_run_nix_managed_switch "$fail_message"'
}

test_install_packages_dispatches_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=true

  local output
  output=$(OS_RELEASE="$osrel" install_packages 2>&1)

  assert_contains "$output" "NixOS"
}

test_set_zsh_default_skips_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=false

  local output
  output=$(OS_RELEASE="$osrel" set_zsh_default 2>&1)

  assert_contains "$output" "declaratively"
}

test_install_nixos_does_not_write_machine_file() {
  DRY=false
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  sudo() { :; }

  install_nixos >/dev/null 2>&1

  if [ -e "$NIXOS_MACHINE_FILE" ]; then
    echo "  FAILED: install_nixos should not write $NIXOS_MACHINE_FILE" >> "$ERROR_FILE"
  fi

  unset -f sudo
  unset NIXOS_MACHINE_FILE
}

test_update_nixos_does_not_write_machine_file() {
  DRY=false
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  sudo() { :; }

  update_nixos >/dev/null 2>&1

  if [ -e "$NIXOS_MACHINE_FILE" ]; then
    echo "  FAILED: update_nixos should not write $NIXOS_MACHINE_FILE" >> "$ERROR_FILE"
  fi

  unset -f sudo
  unset NIXOS_MACHINE_FILE
}
