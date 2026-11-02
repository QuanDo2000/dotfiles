#!/usr/bin/env bash
# Verified upstream Nix archive bootstrap checks.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"
setup() {
  init_test_env
  source_scripts utils.sh packages.sh releases.sh
}
teardown() {
  cleanup_test_env
  unset -f curl _file_sha256 mktemp tar 2>/dev/null || true
}
make_installer_archive() {
  local dir="$TEST_TMPDIR/archive/nix-$NIX_BOOTSTRAP_VERSION-x86_64-linux"
  mkdir -p "$dir"
  printf '#!/bin/sh\n[ "$1" = --daemon ] && [ "$2" = --yes ] && [ "$3" = --no-channel-add ] && [ "$4" = --nix-extra-conf-file ] || exit 92\nprintf "execute:--daemon --yes --no-channel-add\\nconfig:%%s\\n" "$(cat "$5")" >> "%s"\nexit %s\n' "$calls" "${installer_status:-0}" > "$dir/install"
  command tar -cJf "$TEST_TMPDIR/fixture.tar.xz" -C "$TEST_TMPDIR/archive" "${dir##*/}"
}
test_install_nix_verifies_archive_before_extraction_and_execution() {
  local calls="$TEST_TMPDIR/calls.log" fixture_hash
  mock_uname Linux
  mock_uname_m x86_64
  make_installer_archive
  fixture_hash="$(_file_sha256 "$TEST_TMPDIR/fixture.tar.xz")"
  NIX_INSTALLER_X86_64_LINUX_SHA256="$fixture_hash"
  curl() {
    assert_contains "$*" "--proto =https --proto-redir =https --tlsv1.2"
    assert_contains "$*" "https://releases.nixos.org/nix/nix-$NIX_BOOTSTRAP_VERSION/nix-$NIX_BOOTSTRAP_VERSION-x86_64-linux.tar.xz"
    printf 'download\n' >> "$calls"
    cp "$TEST_TMPDIR/fixture.tar.xz" "${!#}"
  }
  _file_sha256() { printf 'verify\n' >> "$calls"; printf '%s\n' "$fixture_hash"; }
  tar() { printf 'extract\n' >> "$calls"; command tar "$@"; }
  _install_nix >/dev/null
  assert_equals $'download\nverify\nextract\nexecute:--daemon --yes --no-channel-add\nconfig:extra-experimental-features = nix-command flakes' "$(<"$calls")"
}
test_install_nix_failures_clean_downloads() {
  local calls="$TEST_TMPDIR/calls" mode status installer_status=1 refresh_dir="$TEST_TMPDIR/bootstrap"
  mock_uname Linux
  mock_uname_m x86_64
  make_installer_archive
  mktemp() { mkdir -p "$refresh_dir"; printf '%s\n' "$refresh_dir"; }
  curl() { cp "$TEST_TMPDIR/fixture.tar.xz" "${!#}"; [[ "$mode" != download ]]; }
  _file_sha256() {
    [[ "$mode" != hash ]] || return 1
    if [[ "$mode" == mismatch ]]; then printf '%064d\n' 0; else _nix_installer_sha256 x86_64-linux; fi
  }
  tar() { [[ "$mode" != extract ]] || return 1; command tar "$@"; }
  for mode in download hash mismatch extract install; do
    status=0
    ( _install_nix ) >/dev/null 2>&1 || status=$?
    assert_equals 1 "$status"
    if [[ "$mode" != install ]]; then
      [[ ! -e "$calls" ]] || assert_equals 'not executed' executed
    else
      assert_equals $'execute:--daemon --yes --no-channel-add\nconfig:extra-experimental-features = nix-command flakes' "$(<"$calls")"
    fi
    [[ ! -e "$refresh_dir" ]] || assert_equals cleaned leftover
  done
}
test_nix_installer_pins_cover_supported_hosts() {
  local target hash
  for target in x86_64-linux aarch64-darwin; do
    hash="$(_nix_installer_sha256 "$target")"
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || assert_equals "64-char $target SHA-256" "$hash"
    assert_equals "https://releases.nixos.org/nix/nix-$NIX_BOOTSTRAP_VERSION/nix-$NIX_BOOTSTRAP_VERSION-$target.tar.xz" "$(_nix_installer_url "$target")"
  done
  mock_uname Darwin
  mock_uname_m arm64
  assert_equals aarch64-darwin "$(_nix_installer_target)"
  mock_uname_m aarch64
  assert_equals aarch64-darwin "$(_nix_installer_target)"
}
test_install_nix_dry_run_and_unsupported_platform_never_download() {
  local marker="$TEST_TMPDIR/downloaded" status=0
  curl() { touch "$marker"; return 1; }
  DRY=true
  _install_nix >/dev/null
  DRY=false
  mock_uname Linux
  mock_uname_m aarch64
  ( _install_nix ) >/dev/null 2>&1 || status=$?
  assert_equals 1 "$status"
  mock_uname_m x86_64
  NIX_INSTALLER_X86_64_LINUX_SHA256=invalid
  status=0
  ( _install_nix ) >/dev/null 2>&1 || status=$?
  assert_equals 1 "$status"
  [[ ! -e "$marker" ]] || assert_equals 'no download' downloaded
}

test_update_nix_installer_pins_keeps_existing_pins_when_download_fails() {
  local target_dir="$DOTFILES_DIR/scripts" packages_file="$DOTFILES_DIR/scripts/packages.sh" before status=0
  mkdir -p "$target_dir"
  cp "$REPO_DIR/scripts/packages.sh" "$packages_file"
  before="$(<"$packages_file")"
  curl() {
    [[ "$*" == *x86_64-linux* ]] || return 1
    printf 'linux' > "${!#}"
  }

  ( _update_nix_installer_pins ) >/dev/null 2>&1 || status=$?

  assert_equals "1" "$status"
  assert_equals "$before" "$(<"$packages_file")"
}

test_update_nix_installer_pins_cleans_downloads_when_write_fails() {
  local refresh_dir="$TEST_TMPDIR/refresh" status=0
  curl() { printf 'artifact' > "${!#}"; }
  _file_sha256() { printf '%064d\n' 1; }
  mktemp() {
    if [[ "${1:-}" == "-d" ]]; then
      mkdir -p "$refresh_dir"
      printf '%s\n' "$refresh_dir"
    else
      command mktemp "$@"
    fi
  }

  ( _update_nix_installer_pins ) >/dev/null 2>&1 || status=$?

  assert_equals "1" "$status"
  [[ ! -e "$refresh_dir" ]] || assert_equals "cleaned refresh directory" "left refresh directory"
}

test_update_nix_installer_pins_skips_unchanged_write() {
  local write_marker="$TEST_TMPDIR/write-called" status=0
  curl() { printf 'artifact' > "${!#}"; }
  _file_sha256() {
    case "$1" in
      *x86_64-linux) _nix_installer_sha256 x86_64-linux ;;
      *aarch64-darwin) _nix_installer_sha256 aarch64-darwin ;;
    esac
  }
  _write_nix_installer_pins() {
    touch "$write_marker"
    return 1
  }

  _update_nix_installer_pins >/dev/null 2>&1 || status=$?

  assert_equals "0" "$status"
  [[ ! -e "$write_marker" ]] || assert_equals "write skipped" "write called"
}

test_update_nix_installer_pins_replaces_both_hashes_atomically() {
  local target_dir="$DOTFILES_DIR/scripts" packages_file="$DOTFILES_DIR/scripts/packages.sh" permissions
  mkdir -p "$target_dir"
  cp "$REPO_DIR/scripts/packages.sh" "$packages_file"
  chmod 0644 "$packages_file"
  permissions="$(ls -ld "$packages_file" | awk '{print $1}')"
  curl() {
    local output="${!#}"
    case "$*" in
      *x86_64-linux*) printf 'linux' > "$output" ;;
      *aarch64-darwin*) printf 'darwin' > "$output" ;;
      *) return 1 ;;
    esac
  }
  _file_sha256() {
    case "$(<"$1")" in
      linux) printf '%064d\n' 1 ;;
      darwin) printf '%064d\n' 2 ;;
    esac
  }

  _update_nix_installer_pins >/dev/null

  assert_contains "$(<"$packages_file")" 'NIX_INSTALLER_X86_64_LINUX_SHA256="0000000000000000000000000000000000000000000000000000000000000001"'
  assert_contains "$(<"$packages_file")" 'NIX_INSTALLER_AARCH64_DARWIN_SHA256="0000000000000000000000000000000000000000000000000000000000000002"'
  assert_equals "$permissions" "$(ls -ld "$packages_file" | awk '{print $1}')"
}
