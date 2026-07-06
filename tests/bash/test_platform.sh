#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh symlinks.sh
}

teardown() {
  cleanup_test_env
}

test_setup_symlinks_is_noop_on_mac() {
  mock_uname Darwin
  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "mac zsh" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  setup_symlinks >/dev/null

  for path in "$HOME/.gitconfig" "$HOME/.zshrc.mac"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "  FAILED: $path should be left for Home Manager on macOS" >> "$ERROR_FILE"
    fi
  done
}

test_setup_symlinks_is_noop_on_linux() {
  mock_uname Linux
  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/config/shared/.gitconfig"

  setup_symlinks >/dev/null

  if [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    echo "  FAILED: .gitconfig should be left for Home Manager on Linux" >> "$ERROR_FILE"
  fi
}

test_install_packages_dispatches_mac() {
  source_scripts packages.sh
  mock_uname Darwin

  DRY=true
  local output
  output=$(install_packages 2>&1)

  assert_contains "$output" "Mac"
}

test_install_debian_dry_run() {
  source_scripts packages.sh

  DRY=true
  local output
  output=$(install_debian 2>&1)

  assert_contains "$output" "Debian"
}

test_install_arch_dry_run() {
  source_scripts packages.sh

  DRY=true
  local output
  output=$(install_arch 2>&1)

  assert_contains "$output" "Arch"
}

test_install_packages_fails_unsupported_os() {
  source_scripts packages.sh
  mock_uname FreeBSD

  local exit_code=0
  (install_packages 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_packages should fail on unsupported OS" >> "$ERROR_FILE"
  fi
}

test_dry_run_darwin_creates_nothing() {
  DRY=true
  mock_uname Darwin
  create_dotfiles_dirs
  echo "content" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  setup_symlinks

  if [ -L "$HOME/.zshrc.mac" ] || [ -f "$HOME/.zshrc.mac" ]; then
    echo "  FAILED: dry run should not create .zshrc.mac" >> "$ERROR_FILE"
  fi
}

test_dry_run_linux_creates_nothing() {
  DRY=true
  mock_uname Linux
  create_dotfiles_dirs
  echo "content" > "$DOTFILES_DIR/config/shared/.gitconfig"

  setup_symlinks

  if [ -L "$HOME/.gitconfig" ] || [ -f "$HOME/.gitconfig" ]; then
    echo "  FAILED: dry run should not create .gitconfig" >> "$ERROR_FILE"
  fi
}

test_detect_platform_nixos() {
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}

test_detect_platform_nixos_precedes_arch() {
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\nID_LIKE="arch"\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}

test_is_home_manager_platform() {
  source_scripts packages.sh

  local platform
  for platform in arch debian nixos mac; do
    if ! is_home_manager_platform "$platform"; then
      echo "  FAILED: $platform should be a Home Manager platform" >> "$ERROR_FILE"
    fi
  done

  if is_home_manager_platform unknown; then
    echo "  FAILED: unknown should not be a Home Manager platform" >> "$ERROR_FILE"
  fi
}

test_is_linux_home_manager_platform() {
  source_scripts packages.sh

  local platform
  for platform in arch debian; do
    if ! is_linux_home_manager_platform "$platform"; then
      echo "  FAILED: $platform should be a Linux Home Manager platform" >> "$ERROR_FILE"
    fi
  done

  for platform in nixos mac unknown; do
    if is_linux_home_manager_platform "$platform"; then
      echo "  FAILED: $platform should not be a Linux Home Manager platform" >> "$ERROR_FILE"
    fi
  done
}
