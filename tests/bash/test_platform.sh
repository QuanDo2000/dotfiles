#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh
}

teardown() {
  cleanup_test_env
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

test_upgrade_system_packages_arch_dry_run() {
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$osrel"

  local output
  output=$(DRY=true OS_RELEASE="$osrel" upgrade_system_packages 2>&1)

  assert_contains "$output" "sudo pacman -Syu"
}

test_upgrade_system_packages_debian_dry_run() {
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$osrel"

  local output
  output=$(DRY=true OS_RELEASE="$osrel" upgrade_system_packages 2>&1)

  assert_contains "$output" "sudo apt-get update"
  assert_contains "$output" "sudo apt-get upgrade -y"
}

test_upgrade_system_packages_mac_dry_run() {
  source_scripts packages.sh
  mock_uname Darwin

  local output
  output=$(DRY=true upgrade_system_packages 2>&1)

  assert_contains "$output" "brew update"
  assert_contains "$output" "brew upgrade --greedy"
}

test_upgrade_system_packages_nixos_uses_managed_update() {
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local output status=0
  output=$(DRY=true OS_RELEASE="$osrel" upgrade_system_packages 2>&1) || status=$?

  assert_equals 1 "$status"
  assert_contains "$output" "dotfile update"
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
