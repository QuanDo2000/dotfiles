#!/usr/bin/env bash
# Verified Lix installer bootstrap checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh releases.sh
}

teardown() {
  cleanup_test_env
  unset -f curl _file_sha256 mktemp 2>/dev/null || true
}

test_install_lix_verifies_download_before_execution() {
  local calls="$TEST_TMPDIR/calls.log"
  mock_uname Linux
  mock_uname_m x86_64
  curl() {
    local output="${!#}"
    case "$*" in
      *tar.xz*)
        printf '%s\n' download-package >> "$calls"
        printf 'package' > "$output"
        ;;
      *)
        printf '%s\n' download-installer >> "$calls"
        cat > "$output" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "execute:\$*" >> "$calls"
EOF
        ;;
    esac
  }
  _file_sha256() {
    case "$1" in
      *lix-package*)
        printf '%s\n' verify-package >> "$calls"
        _lix_package_sha256 x86_64-linux
        ;;
      *)
        printf '%s\n' verify-installer >> "$calls"
        _lix_installer_sha256 x86_64-linux
        ;;
    esac
  }

  _install_lix >/dev/null

  assert_equals $'download-installer\nverify-installer\ndownload-package\nverify-package' "$(head -n 4 "$calls")"
  assert_contains "$(<"$calls")" 'execute:install --no-confirm --nix-package-url '
}

test_install_lix_rejects_checksum_mismatch_before_execution() {
  local marker="$TEST_TMPDIR/executed"
  mock_uname Linux
  mock_uname_m x86_64
  curl() {
    local output="${!#}"
    cat > "$output" <<EOF
#!/usr/bin/env bash
touch "$marker"
EOF
  }
  _file_sha256() { printf '%064d\n' 0; }

  local status=0
  ( _install_lix ) >/dev/null 2>&1 || status=$?
  assert_equals "1" "$status"
  [[ ! -e "$marker" ]] || assert_equals "not executed" "executed"
}

test_install_lix_rejects_package_checksum_mismatch_before_execution() {
  local marker="$TEST_TMPDIR/executed"
  mock_uname Linux
  mock_uname_m x86_64
  curl() {
    local output="${!#}"
    case "$*" in
      *tar.xz*) printf 'package' > "$output" ;;
      *) printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" > "$output" ;;
    esac
  }
  _file_sha256() {
    case "$1" in
      *lix-package*) printf '%064d\n' 0 ;;
      *) _lix_installer_sha256 x86_64-linux ;;
    esac
  }

  local status=0
  ( _install_lix ) >/dev/null 2>&1 || status=$?
  assert_equals "1" "$status"
  [[ ! -e "$marker" ]] || assert_equals "not executed" "executed"
}

test_lix_installer_pins_cover_supported_hosts() {
  local target installer_hash package_hash
  for target in x86_64-linux aarch64-darwin; do
    installer_hash="$(_lix_installer_sha256 "$target")"
    package_hash="$(_lix_package_sha256 "$target")"
    [[ "$installer_hash" =~ ^[0-9a-f]{64}$ ]] || assert_equals "64-char $target installer SHA-256" "$installer_hash"
    [[ "$package_hash" =~ ^[0-9a-f]{64}$ ]] || assert_equals "64-char $target package SHA-256" "$package_hash"
    assert_contains "$(_lix_package_url "$target")" "lix-$LIX_BOOTSTRAP_VERSION-$target.tar.xz"
  done
  assert_not_contains "$(<"$REPO_DIR/scripts/packages.sh")" '| sh'
}

test_update_lix_installer_pins_keeps_existing_pins_when_download_fails() {
  local target_dir="$DOTFILES_DIR/scripts" packages_file="$DOTFILES_DIR/scripts/packages.sh" before status=0
  mkdir -p "$target_dir"
  cp "$REPO_DIR/scripts/packages.sh" "$packages_file"
  before="$(<"$packages_file")"
  curl() {
    [[ "$*" == *x86_64-linux* ]] || return 1
    printf 'linux' > "${!#}"
  }

  ( _update_lix_installer_pins ) >/dev/null 2>&1 || status=$?

  assert_equals "1" "$status"
  assert_equals "$before" "$(<"$packages_file")"
}

test_update_lix_installer_pins_cleans_downloads_when_write_fails() {
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

  ( _update_lix_installer_pins ) >/dev/null 2>&1 || status=$?

  assert_equals "1" "$status"
  [[ ! -e "$refresh_dir" ]] || assert_equals "cleaned refresh directory" "left refresh directory"
}

test_update_lix_installer_pins_replaces_both_hashes_atomically() {
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

  _update_lix_installer_pins >/dev/null

  assert_contains "$(<"$packages_file")" 'LIX_INSTALLER_X86_64_LINUX_SHA256="0000000000000000000000000000000000000000000000000000000000000001"'
  assert_contains "$(<"$packages_file")" 'LIX_INSTALLER_AARCH64_DARWIN_SHA256="0000000000000000000000000000000000000000000000000000000000000002"'
  assert_equals "$permissions" "$(ls -ld "$packages_file" | awk '{print $1}')"
}
