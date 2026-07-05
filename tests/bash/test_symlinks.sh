#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh symlinks.sh
}

teardown() {
  cleanup_test_env
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
  echo "#!/usr/bin/env bash" > "$root/bin/myscript"

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

test_link_files_overwrite_all() {
  local overwrite_all=true backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  local old_target="$TEST_TMPDIR/oldtarget"
  echo "old" > "$old_target"
  echo "new" > "$src"
  ln -s "$old_target" "$dst"

  link_files "$src" "$dst"

  assert_symlink "$dst" "$src"
}

test_link_files_backup_all() {
  local overwrite_all=false backup_all=true skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  link_files "$src" "$dst"

  assert_file_exists "${dst}.backup"
  assert_symlink "$dst" "$src"
}

test_link_files_skip_all() {
  local overwrite_all=false backup_all=false skip_all=true
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  link_files "$src" "$dst"

  if [ -L "$dst" ]; then
    echo "  FAILED: dst should still be a regular file, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$dst"
}

# ---------------------------------------------------------------------------
# Interactive single-file prompt choices (pipe input to stdin)
# ---------------------------------------------------------------------------

test_link_files_interactive_overwrite() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  local old_target="$TEST_TMPDIR/oldtarget"
  echo "old" > "$old_target"
  echo "new" > "$src"
  ln -s "$old_target" "$dst"

  echo -n "o" | link_files "$src" "$dst"

  assert_symlink "$dst" "$src"
}

test_link_files_interactive_backup() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  echo -n "b" | link_files "$src" "$dst"

  assert_file_exists "${dst}.backup"
  assert_symlink "$dst" "$src"
}

test_link_files_interactive_skip() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  echo -n "s" | link_files "$src" "$dst"

  if [ -L "$dst" ]; then
    echo "  FAILED: dst should still be a regular file after skip" >> "$ERROR_FILE"
  fi
  assert_file_exists "$dst"
}

test_link_files_interactive_overwrite_all() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  local old_target="$TEST_TMPDIR/oldtarget"
  echo "old" > "$old_target"
  echo "new" > "$src"
  ln -s "$old_target" "$dst"

  echo -n "O" | link_files "$src" "$dst"

  assert_symlink "$dst" "$src"
}

test_link_files_interactive_backup_all() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  echo -n "B" | link_files "$src" "$dst"

  assert_file_exists "${dst}.backup"
  assert_symlink "$dst" "$src"
}

test_link_files_interactive_skip_all() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "new" > "$src"
  echo "existing" > "$dst"

  echo -n "S" | link_files "$src" "$dst"

  if [ -L "$dst" ]; then
    echo "  FAILED: dst should still be a regular file after Skip all" >> "$ERROR_FILE"
  fi
  assert_file_exists "$dst"
}

test_link_files_interactive_invalid_input_skips() {
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  local old_target="$TEST_TMPDIR/oldtarget"
  echo "old" > "$old_target"
  echo "new" > "$src"
  ln -s "$old_target" "$dst"

  echo -n "x" | link_files "$src" "$dst"

  # Invalid input should default to skip — dst keeps pointing at old target
  assert_symlink "$dst" "$old_target"
}

# ---------------------------------------------------------------------------

test_setup_symlinks_folder_nonexistent_root() {
  local overwrite_all=false backup_all=false skip_all=false
  local before_count
  before_count="$(find "$HOME" -mindepth 1 | wc -l)"

  setup_symlinks_folder "$TEST_TMPDIR/does_not_exist"

  local after_count
  after_count="$(find "$HOME" -mindepth 1 | wc -l)"
  assert_equals "$before_count" "$after_count"
}

test_setup_symlinks_folder_creates_local_bin() {
  local overwrite_all=false backup_all=false skip_all=false
  rm -rf "$HOME/.local/bin"
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root/bin"
  echo "#!/usr/bin/env bash" > "$root/bin/mytool"

  setup_symlinks_folder "$root"

  if [ ! -d "$HOME/.local/bin" ]; then
    echo "  FAILED: \$HOME/.local/bin was not created" >> "$ERROR_FILE"
  fi
  assert_symlink "$HOME/.local/bin/mytool" "$root/bin/mytool"
}

test_setup_symlinks_folder_creates_config() {
  local overwrite_all=false backup_all=false skip_all=false
  rm -rf "$HOME/.config"
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root/config/myapp"
  echo "setting=1" > "$root/config/myapp/config.toml"

  setup_symlinks_folder "$root"

  if [ ! -d "$HOME/.config" ]; then
    echo "  FAILED: \$HOME/.config was not created" >> "$ERROR_FILE"
  fi
  assert_symlink "$HOME/.config/myapp" "$root/config/myapp"
}

# ---------------------------------------------------------------------------
# Error paths: filesystem operation failures
# ---------------------------------------------------------------------------

test_link_files_fails_unwritable_dst_dir() {
  # chmod 555 does not prevent the owner from writing on Windows NTFS.
  is_windows_bash && return 0
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst_dir="$TEST_TMPDIR/readonly"
  mkdir -p "$dst_dir"
  echo "content" > "$src"
  chmod 555 "$dst_dir"

  local exit_code=0
  (link_files "$src" "$dst_dir/dstfile" 2>&1) || exit_code=$?

  chmod 755 "$dst_dir"  # restore so teardown can clean up
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: link_files should fail with unwritable destination dir" >> "$ERROR_FILE"
  fi
}

test_link_files_broken_source() {
  # Symlinking to a non-existent source should still succeed (ln -s is happy
  # to create dangling symlinks); we only require the link itself to exist.
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/does_not_exist"
  local dst="$TEST_TMPDIR/home/dstfile"

  link_files "$src" "$dst"

  if [ ! -L "$dst" ]; then
    echo "  FAILED: dangling symlink $dst was not created" >> "$ERROR_FILE"
  fi
  assert_symlink "$dst" "$src"
}

test_link_files_idempotent_relative_symlink() {
  # If an existing symlink points to the same absolute target via a relative
  # path, link_files should treat it as already-linked and skip.
  local overwrite_all=false backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst="$TEST_TMPDIR/home/dstfile"
  echo "content" > "$src"
  # Create a relative symlink that resolves to $src.
  ( cd "$TEST_TMPDIR/home" && ln -s "../srcfile" "dstfile" )

  local output
  output=$(link_files "$src" "$dst" 2>&1)

  assert_contains "$output" "Skipped"
}

test_link_files_overwrite_fails_unwritable() {
  # chmod 555 does not prevent the owner from writing on Windows NTFS.
  is_windows_bash && return 0
  local overwrite_all=true backup_all=false skip_all=false
  local src="$TEST_TMPDIR/srcfile"
  local dst_dir="$TEST_TMPDIR/readonly"
  mkdir -p "$dst_dir"
  echo "new" > "$src"
  echo "existing" > "$dst_dir/dstfile"
  chmod 555 "$dst_dir"

  local exit_code=0
  (link_files "$src" "$dst_dir/dstfile" 2>&1) || exit_code=$?

  chmod 755 "$dst_dir"
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: link_files overwrite should fail with unwritable dir" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Edge cases: paths with spaces and dotted/hidden directories
# ---------------------------------------------------------------------------

test_setup_symlinks_folder_path_with_spaces() {
  local root="$TEST_TMPDIR/dir with spaces"
  mkdir -p "$root/config/my app"
  echo "hello" > "$root/config/my app/conf"
  echo "x" > "$root/.gitconfig"

  setup_symlinks_folder "$root"

  assert_symlink "$HOME/.gitconfig" "$root/.gitconfig"
  assert_symlink "$HOME/.config/my app" "$root/config/my app"
}

test_setup_symlinks_folder_dotted_config_subdir() {
  local root="$TEST_TMPDIR/fakedir"
  mkdir -p "$root/config/.hidden"
  echo "secret" > "$root/config/.hidden/conf"

  setup_symlinks_folder "$root"

  assert_symlink "$HOME/.config/.hidden" "$root/config/.hidden"
}

# ---------------------------------------------------------------------------
# AI tool carveouts: tool configs are linked only when the tool is installed.
# ---------------------------------------------------------------------------

create_fake_command() {
  local name="$1"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n' > "$HOME/.local/bin/$name"
  chmod +x "$HOME/.local/bin/$name"
  PATH="$HOME/.local/bin:$PATH"
}

test_setup_symlinks_links_claude_settings() {
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  mock_uname Linux
  create_dotfiles_dirs
  create_fake_command claude
  mkdir -p "$DOTFILES_DIR/config/shared/ai/claude"
  echo '{"enabledPlugins":{}}' > "$DOTFILES_DIR/config/shared/ai/claude/settings.json"

  OS_RELEASE="$osrel" setup_symlinks

  assert_symlink "$HOME/.claude/settings.json" \
    "$DOTFILES_DIR/config/shared/ai/claude/settings.json"
}

test_setup_symlinks_links_codex_config() {
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  mock_uname Linux
  create_dotfiles_dirs
  create_fake_command codex
  mkdir -p "$DOTFILES_DIR/config/shared/ai/codex"
  echo 'model = "gpt-5.5"' > "$DOTFILES_DIR/config/shared/ai/codex/config.toml"

  OS_RELEASE="$osrel" setup_symlinks

  assert_symlink "$HOME/.codex/config.toml" \
    "$DOTFILES_DIR/config/shared/ai/codex/config.toml"
}

test_setup_symlinks_skips_ai_tools_when_commands_missing() {
  create_dotfiles_dirs
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        claude|codex) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  mkdir -p "$DOTFILES_DIR/config/shared/ai/claude"
  echo '{}' > "$DOTFILES_DIR/config/shared/ai/claude/settings.json"

  setup_symlinks

  unset -f command

  if [ -e "$HOME/.claude/settings.json" ] || [ -L "$HOME/.claude/settings.json" ]; then
    echo "  FAILED: claude settings should not be linked when claude is missing" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_skips_ai_when_missing() {
  # When the source files don't exist in the repo, setup_symlinks must not
  # create $HOME/.claude parent dirs.
  create_dotfiles_dirs

  setup_symlinks

  if [ -d "$HOME/.claude" ]; then
    echo "  FAILED: $HOME/.claude should not be created without source" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_ai_dry_run() {
  DRY=true
  create_dotfiles_dirs
  create_fake_command claude
  mkdir -p "$DOTFILES_DIR/config/shared/ai/claude"
  echo '{}' > "$DOTFILES_DIR/config/shared/ai/claude/settings.json"

  setup_symlinks

  if [ -e "$HOME/.claude/settings.json" ] || [ -L "$HOME/.claude/settings.json" ]; then
    echo "  FAILED: claude settings should not be linked in dry run" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_skips_home_manager_files_on_nixos() {
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  mock_uname Linux
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/shared/.ssh" \
    "$DOTFILES_DIR/config/shared/ai/claude" \
    "$DOTFILES_DIR/config/shared/ai/codex"
  echo "git" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "vim" > "$DOTFILES_DIR/config/shared/.vimrc"
  echo "tmux" > "$DOTFILES_DIR/config/unix/.tmux.conf"
  echo "ssh" > "$DOTFILES_DIR/config/shared/.ssh/config"
  echo '{}' > "$DOTFILES_DIR/config/shared/ai/claude/settings.json"
  echo 'model = "gpt-5.5"' > "$DOTFILES_DIR/config/shared/ai/codex/config.toml"
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"

  OS_RELEASE="$osrel" setup_symlinks

  for path in \
    "$HOME/.gitconfig" \
    "$HOME/.vimrc" \
    "$HOME/.tmux.conf" \
    "$HOME/.ssh/config" \
    "$HOME/.claude/settings.json" \
    "$HOME/.codex/config.toml" \
    "$HOME/.local/bin/dotfile"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "  FAILED: $path should be left for Home Manager on NixOS" >> "$ERROR_FILE"
    fi
  done
  assert_file_exists "$HOME/.zshrc"
}

test_setup_symlinks_skips_home_manager_files_on_arch() {
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$osrel"
  mock_uname Linux
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/shared/config" "$DOTFILES_DIR/config/unix/config/ghostty"
  echo 'format = "$character"' > "$DOTFILES_DIR/config/shared/config/starship.toml"
  echo 'font-family = "FiraCode Nerd Font"' > "$DOTFILES_DIR/config/unix/config/ghostty/config"
  ln -s "$DOTFILES_DIR/config/unix/config/ghostty" "$HOME/.config/ghostty"
  FORCE=true

  OS_RELEASE="$osrel" setup_symlinks

  if [ -e "$HOME/.config/starship.toml" ] || [ -L "$HOME/.config/starship.toml" ]; then
    echo "  FAILED: $HOME/.config/starship.toml should be left for Home Manager on Arch" >> "$ERROR_FILE"
  fi
  if [ -L "$DOTFILES_DIR/config/unix/config/ghostty/config" ]; then
    echo "  FAILED: repo Ghostty config should not become a self-symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$DOTFILES_DIR/config/unix/config/ghostty/config"
  assert_file_exists "$HOME/.zshrc"
}

test_setup_symlinks_skips_home_manager_files_on_mac() {
  mock_uname Darwin
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/mac/bin"
  echo "git" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "mac" > "$DOTFILES_DIR/config/mac/.zshrc.mac"
  echo "#!/usr/bin/env bash" > "$DOTFILES_DIR/config/mac/bin/caf"
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"

  setup_symlinks

  for path in "$HOME/.gitconfig" "$HOME/.zshrc.mac" "$HOME/.local/bin/caf" "$HOME/.local/bin/dotfile"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "  FAILED: $path should be left for Home Manager on macOS" >> "$ERROR_FILE"
    fi
  done
  assert_file_exists "$HOME/.zshrc"
}

test_setup_symlinks_links_starship_config_on_non_home_manager_linux() {
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "$osrel"
  mock_uname Linux
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/shared/config"
  echo 'format = "$character"' > "$DOTFILES_DIR/config/shared/config/starship.toml"

  OS_RELEASE="$osrel" setup_symlinks

  assert_symlink "$HOME/.config/starship.toml" \
    "$DOTFILES_DIR/config/shared/config/starship.toml"
}

test_setup_symlinks_no_stray_starship_in_home() {
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/shared/config"
  echo 'format = "$character"' > "$DOTFILES_DIR/config/shared/config/starship.toml"

  setup_symlinks

  if [ -e "$HOME/starship.toml" ] || [ -L "$HOME/starship.toml" ]; then
    echo "  FAILED: ~/starship.toml stray link should not be created" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Machine-local ~/.zshrc stub (_ensure_local_zshrc)
# ---------------------------------------------------------------------------

test_ensure_local_zshrc_creates_stub_when_missing() {
  DOTFILES_DIR="$TEST_TMPDIR/dotfiles"
  rm -f "$HOME/.zshrc"

  _ensure_local_zshrc

  assert_file_exists "$HOME/.zshrc"
  if [ -L "$HOME/.zshrc" ]; then
    echo "  FAILED: ~/.zshrc should be a real file, not a symlink" >> "$ERROR_FILE"
  fi
  assert_contains "$(cat "$HOME/.zshrc")" 'source "$HOME/.zshrc.base"'
}

test_ensure_local_zshrc_replaces_repo_symlink() {
  DOTFILES_DIR="$TEST_TMPDIR/dotfiles"
  mkdir -p "$DOTFILES_DIR/config/unix"
  echo "old tracked zshrc" > "$DOTFILES_DIR/config/unix/.zshrc"
  ln -sf "$DOTFILES_DIR/config/unix/.zshrc" "$HOME/.zshrc"

  _ensure_local_zshrc

  if [ -L "$HOME/.zshrc" ]; then
    echo "  FAILED: repo-linked ~/.zshrc should be replaced by a real stub" >> "$ERROR_FILE"
  fi
  assert_contains "$(cat "$HOME/.zshrc")" 'source "$HOME/.zshrc.base"'
}

test_ensure_local_zshrc_preserves_existing_local_file() {
  DOTFILES_DIR="$TEST_TMPDIR/dotfiles"
  printf 'my machine-local config\n' > "$HOME/.zshrc"

  _ensure_local_zshrc

  # Must NOT clobber a real (non-repo) ~/.zshrc — that's where installers append.
  assert_contains "$(cat "$HOME/.zshrc")" "my machine-local config"
}

test_ensure_local_zshrc_dry_run_creates_nothing() {
  DRY=true
  DOTFILES_DIR="$TEST_TMPDIR/dotfiles"
  rm -f "$HOME/.zshrc"

  _ensure_local_zshrc

  if [ -e "$HOME/.zshrc" ]; then
    echo "  FAILED: dry run should not create ~/.zshrc" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_links_caf_on_mac() {
  local overwrite_all=false backup_all=false skip_all=false

  mkdir -p "$DOTFILES_DIR/config/mac/bin"
  cp "$REPO_DIR/config/mac/bin/caf" "$DOTFILES_DIR/config/mac/bin/caf"
  chmod +x "$DOTFILES_DIR/config/mac/bin/caf"

  setup_symlinks_folder "$DOTFILES_DIR/config/mac"

  assert_symlink "$HOME/.local/bin/caf" "$DOTFILES_DIR/config/mac/bin/caf"
}
