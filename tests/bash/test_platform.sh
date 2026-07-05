#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh symlinks.sh
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# Mac: Home Manager owns shared/unix/mac links
# ---------------------------------------------------------------------------

test_setup_symlinks_skips_home_manager_files_on_darwin() {
  mock_uname Darwin
  local overwrite_all=false backup_all=false skip_all=false

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "mac zsh" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  setup_symlinks

  if [ -e "$HOME/.zshrc.mac" ] || [ -L "$HOME/.zshrc.mac" ]; then
    echo "  FAILED: .zshrc.mac should be left for Home Manager on macOS" >> "$ERROR_FILE"
  fi
  if [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    echo "  FAILED: .gitconfig should be left for Home Manager on macOS" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Linux: setup_symlinks excludes mac/ folder
# ---------------------------------------------------------------------------

test_setup_symlinks_excludes_mac_on_linux() {
  mock_uname Linux
  local overwrite_all=false backup_all=false skip_all=false

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "mac zsh" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  setup_symlinks

  if [ -L "$HOME/.zshrc.mac" ] || [ -f "$HOME/.zshrc.mac" ]; then
    echo "  FAILED: .zshrc.mac should not exist on Linux" >> "$ERROR_FILE"
  fi
  assert_symlink "$HOME/.gitconfig" "$DOTFILES_DIR/config/shared/.gitconfig"
}

# ---------------------------------------------------------------------------
# Mac: setup_symlinks_folder handles mac dotfiles, config, and bin
# ---------------------------------------------------------------------------

test_mac_folder_dotfiles() {
  local overwrite_all=false backup_all=false skip_all=false

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir"
  echo "mac zshrc" > "$mac_dir/.zshrc.mac"
  echo "mac gitconfig" > "$mac_dir/.gitconfig.mac"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.zshrc.mac" "$mac_dir/.zshrc.mac"
  assert_symlink "$HOME/.gitconfig.mac" "$mac_dir/.gitconfig.mac"
}

test_mac_folder_config() {
  local overwrite_all=false backup_all=false skip_all=false

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir/config/ghostty"
  echo "font-size=14" > "$mac_dir/config/ghostty/config"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.config/ghostty/config" "$mac_dir/config/ghostty/config"
}

test_mac_folder_bin() {
  local overwrite_all=false backup_all=false skip_all=false

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir/bin"
  echo "#!/usr/bin/env bash" > "$mac_dir/bin/mac-tool"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.local/bin/mac-tool" "$mac_dir/bin/mac-tool"
}

# ---------------------------------------------------------------------------
# Mac: force flag still does not overwrite Home Manager links
# ---------------------------------------------------------------------------

test_force_does_not_overwrite_home_manager_files_darwin() {
  FORCE=true
  mock_uname Darwin
  local overwrite_all=false backup_all=false skip_all=false

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "mac" > "$DOTFILES_DIR/config/mac/.zshrc.mac"

  echo "old" > "$HOME/.gitconfig"
  echo "old mac" > "$HOME/.zshrc.mac"

  setup_symlinks

  if [ -L "$HOME/.gitconfig" ] || [ "$(cat "$HOME/.gitconfig")" != "old" ]; then
    echo "  FAILED: force should not replace Home Manager-owned .gitconfig on macOS" >> "$ERROR_FILE"
  fi
  if [ -L "$HOME/.zshrc.mac" ] || [ "$(cat "$HOME/.zshrc.mac")" != "old mac" ]; then
    echo "  FAILED: force should not replace Home Manager-owned .zshrc.mac on macOS" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# install_packages: dispatches to correct platform installer
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Dry-run: no files created on either platform
# ---------------------------------------------------------------------------

test_dry_run_darwin_creates_nothing() {
  DRY=true
  mock_uname Darwin
  local overwrite_all=false backup_all=false skip_all=false

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
  local overwrite_all=false backup_all=false skip_all=false

  create_dotfiles_dirs
  echo "content" > "$DOTFILES_DIR/config/shared/.gitconfig"

  setup_symlinks

  if [ -L "$HOME/.gitconfig" ] || [ -f "$HOME/.gitconfig" ]; then
    echo "  FAILED: dry run should not create .gitconfig" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# detect_platform: NixOS
# ---------------------------------------------------------------------------

test_detect_platform_nixos() {
  source_scripts packages.sh   # pulls in platform.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}

test_detect_platform_nixos_precedes_arch() {
  # A NixOS os-release must not be misread as arch even if ID_LIKE mentions it.
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\nID_LIKE="arch"\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}
