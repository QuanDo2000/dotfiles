#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh symlinks.sh
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# Mac: setup_symlinks includes mac/ folder on Darwin
# ---------------------------------------------------------------------------

test_setup_symlinks_includes_mac_on_darwin() {
  mock_uname Darwin
  eval "$(init_symlink_vars)"

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/shared/.gitconfig"
  echo "mac zsh" > "$DOTFILES_DIR/mac/.zshrc.mac"

  setup_symlinks

  assert_symlink "$HOME/.zshrc.mac" "$DOTFILES_DIR/mac/.zshrc.mac"
  assert_symlink "$HOME/.gitconfig" "$DOTFILES_DIR/shared/.gitconfig"
}

# ---------------------------------------------------------------------------
# Linux: setup_symlinks excludes mac/ folder
# ---------------------------------------------------------------------------

test_setup_symlinks_excludes_mac_on_linux() {
  mock_uname Linux
  eval "$(init_symlink_vars)"

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/shared/.gitconfig"
  echo "mac zsh" > "$DOTFILES_DIR/mac/.zshrc.mac"

  setup_symlinks

  if [ -L "$HOME/.zshrc.mac" ] || [ -f "$HOME/.zshrc.mac" ]; then
    echo "  FAILED: .zshrc.mac should not exist on Linux" >> "$ERROR_FILE"
  fi
  assert_symlink "$HOME/.gitconfig" "$DOTFILES_DIR/shared/.gitconfig"
}

# ---------------------------------------------------------------------------
# Mac: setup_symlinks_folder handles mac dotfiles, config, and bin
# ---------------------------------------------------------------------------

test_mac_folder_dotfiles() {
  eval "$(init_symlink_vars)"

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir"
  echo "mac zshrc" > "$mac_dir/.zshrc.mac"
  echo "mac gitconfig" > "$mac_dir/.gitconfig.mac"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.zshrc.mac" "$mac_dir/.zshrc.mac"
  assert_symlink "$HOME/.gitconfig.mac" "$mac_dir/.gitconfig.mac"
}

test_mac_folder_config() {
  eval "$(init_symlink_vars)"

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir/config/ghostty"
  echo "font-size=14" > "$mac_dir/config/ghostty/config"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.config/ghostty" "$mac_dir/config/ghostty"
}

test_mac_folder_bin() {
  eval "$(init_symlink_vars)"

  local mac_dir="$TEST_TMPDIR/mac"
  mkdir -p "$mac_dir/bin"
  echo "#!/bin/bash" > "$mac_dir/bin/mac-tool"

  setup_symlinks_folder "$mac_dir"

  assert_symlink "$HOME/.local/bin/mac-tool" "$mac_dir/bin/mac-tool"
}

# ---------------------------------------------------------------------------
# Mac: force flag overwrites across all platform folders
# ---------------------------------------------------------------------------

test_force_overwrite_all_platforms_darwin() {
  FORCE=true
  mock_uname Darwin
  eval "$(init_symlink_vars)"

  create_dotfiles_dirs
  echo "shared" > "$DOTFILES_DIR/shared/.gitconfig"
  echo "mac" > "$DOTFILES_DIR/mac/.zshrc.mac"

  echo "old" > "$HOME/.gitconfig"
  echo "old mac" > "$HOME/.zshrc.mac"

  setup_symlinks

  assert_symlink "$HOME/.gitconfig" "$DOTFILES_DIR/shared/.gitconfig"
  assert_symlink "$HOME/.zshrc.mac" "$DOTFILES_DIR/mac/.zshrc.mac"
}

# ---------------------------------------------------------------------------
# install_neovim: skips on Darwin, runs on Linux
# ---------------------------------------------------------------------------

test_install_neovim_skips_on_darwin() {
  source_scripts packages.sh
  mock_uname Darwin

  local output
  output=$(install_neovim 2>&1)

  assert_equals "" "$output"
}

test_install_neovim_runs_on_linux() {
  source_scripts packages.sh
  mock_uname Linux

  DRY=true
  local output
  output=$(install_neovim 2>&1)

  assert_contains "$output" "neovim"
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
  eval "$(init_symlink_vars)"

  create_dotfiles_dirs
  echo "content" > "$DOTFILES_DIR/mac/.zshrc.mac"

  setup_symlinks

  if [ -L "$HOME/.zshrc.mac" ] || [ -f "$HOME/.zshrc.mac" ]; then
    echo "  FAILED: dry run should not create .zshrc.mac" >> "$ERROR_FILE"
  fi
}

test_dry_run_linux_creates_nothing() {
  DRY=true
  mock_uname Linux
  eval "$(init_symlink_vars)"

  create_dotfiles_dirs
  echo "content" > "$DOTFILES_DIR/shared/.gitconfig"

  setup_symlinks

  if [ -L "$HOME/.gitconfig" ] || [ -f "$HOME/.gitconfig" ]; then
    echo "  FAILED: dry run should not create .gitconfig" >> "$ERROR_FILE"
  fi
}
