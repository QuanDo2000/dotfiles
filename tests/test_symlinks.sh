#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
  source "$REPO_DIR/scripts/symlinks.sh"

  TEST_TMPDIR="$(mktemp -d)"
  ORIG_HOME="$HOME"
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME" "$HOME/.config" "$HOME/.local/bin"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_TMPDIR"
}

test_link_files_creates_symlink() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "content" > "$src"

  link_files "$src" "$dst"

  assert_symlink "$dst" "$src"
}

test_link_files_skips_existing() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "content" > "$src"
  ln -s "$src" "$dst"

  local output
  output=$(link_files "$src" "$dst" 2>&1)

  assert_contains "$output" "Skipped"
}

test_copy_file_copies() {
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "hello" > "$src"

  copy_file "$src" "$dst"

  assert_file_exists "$dst"
  local actual
  actual="$(cat "$dst")"
  assert_equals "hello" "$actual"
}

test_copy_file_skips_identical() {
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "same" > "$src"
  echo "same" > "$dst"

  local output
  output=$(copy_file "$src" "$dst" 2>&1)

  assert_contains "$output" "Skipped"
}

test_copy_file_force_overwrites() {
  FORCE=true
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new content" > "$src"
  echo "old content" > "$dst"

  copy_file "$src" "$dst"

  local actual
  actual="$(cat "$dst")"
  assert_equals "new content" "$actual"
}

test_dry_run_link() {
  DRY=true
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "content" > "$src"

  link_files "$src" "$dst"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  FAILED: dst should not exist in dry run" >> "$ERROR_FILE"
  fi
}

test_dry_run_copy() {
  DRY=true
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "content" > "$src"

  copy_file "$src" "$dst"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  FAILED: dst should not exist in dry run" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_folder_files() {
  local overwrite_all=false backup_all=false skip_all=false
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root"
  echo "dotfile" > "$root/.gitconfig"
  echo "vimrc" > "$root/.vimrc"

  setup_symlinks_folder "$root"

  assert_symlink "$HOME/.gitconfig" "$root/.gitconfig"
  assert_symlink "$HOME/.vimrc" "$root/.vimrc"
}

test_setup_symlinks_folder_bin() {
  local overwrite_all=false backup_all=false skip_all=false
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root/bin"
  echo "#!/bin/bash" > "$root/bin/myscript"

  setup_symlinks_folder "$root"

  assert_symlink "$HOME/.local/bin/myscript" "$root/bin/myscript"
}

test_setup_symlinks_folder_config() {
  local overwrite_all=false backup_all=false skip_all=false
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root/config/nvim"
  echo "init" > "$root/config/nvim/init.lua"

  setup_symlinks_folder "$root"

  assert_symlink "$HOME/.config/nvim" "$root/config/nvim"
}

test_setup_symlinks_folder_zshrc_copied() {
  local overwrite_all=false backup_all=false skip_all=false
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root"
  echo "zsh config" > "$root/.zshrc"

  setup_symlinks_folder "$root"

  assert_file_exists "$HOME/.zshrc"
  # Must be a regular file, not a symlink
  if [ -L "$HOME/.zshrc" ]; then
    echo "  FAILED: .zshrc should be a regular file, not a symlink" >> "$ERROR_FILE"
  fi
  local actual
  actual="$(cat "$HOME/.zshrc")"
  assert_equals "zsh config" "$actual"
}
