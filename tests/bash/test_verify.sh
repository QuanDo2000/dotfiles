#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  unset -f command 2>/dev/null || true
  source_scripts utils.sh verify.sh
}

teardown() {
  cleanup_test_env
}

with_nix_agent_tools() {
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" =~ ^(codex|codebase-memory-mcp)$ ]]; then
      printf '/nix/store/test-%s/bin/%s\n' "$2" "$2"
      return 0
    fi
    builtin command "$@"
  }
}

test_verify_tool_found() {
  local output
  output=$(
    if command -v bash >/dev/null 2>&1; then
      success "bash found: $(command -v bash)"
    else
      fail_soft "bash not found"
    fi
  )
  assert_contains "$output" "bash found"
}

test_verify_tool_missing() {
  local output
  output=$(
    if command -v nonexistent_tool_xyz >/dev/null 2>&1; then
      success "found"
    else
      fail_soft "nonexistent_tool_xyz not found"
    fi
  )
  assert_contains "$output" "nonexistent_tool_xyz not found"
}

test_verify_symlink_valid() {
  mkdir -p "$DOTFILES_DIR"
  echo "content" > "$DOTFILES_DIR/.vimrc"
  ln -s "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"

  if [[ ! -L "$HOME/.vimrc" ]]; then
    echo "  Expected $HOME/.vimrc to be a symlink" >> "$ERROR_FILE"
    return
  fi
  local link_target
  link_target="$(readlink "$HOME/.vimrc")"
  assert_contains "$link_target" "$DOTFILES_DIR"
}

test_verify_file_not_symlink() {
  echo "not a symlink" > "$HOME/.vimrc"
  if [[ -L "$HOME/.vimrc" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
  assert_file_exists "$HOME/.vimrc"
}

test_verify_error_count() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "issue(s) found"
}

test_verify_is_a_small_smoke_check() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(verify 2>&1) || true
  if [[ "$output" == *"starship"* || "$output" == *"zsh plugin"* || "$output" == *"tmux plugin"* ]]; then
    echo "  FAILED: verify should only smoke-check core symlinks and local zshrc" >> "$ERROR_FILE"
  fi
}

test_verify_symlink_wrong_target() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/other"
  echo "content" > "$HOME/other/.vimrc"
  ln -s "$HOME/other/.vimrc" "$HOME/.vimrc"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "expected"
}

test_verify_requires_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    echo "content" > "$DOTFILES_DIR/$f"
    mkdir -p "$(dirname "$HOME/$f")"
    ln -s "$DOTFILES_DIR/$f" "$HOME/$f"
  done
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  rm -f "$HOME/.local/bin/dotfile"

  local output
  output=$(verify 2>&1) || true

  assert_contains "$output" ".local/bin/dotfile not found"
}

test_verify_accepts_repo_dotfile_command_link() {
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    echo "content" > "$DOTFILES_DIR/$f"
    mkdir -p "$(dirname "$HOME/$f")"
    ln -s "$DOTFILES_DIR/$f" "$HOME/$f"
  done
  echo '#!/usr/bin/env bash' > "$DOTFILES_DIR/dotfile"
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(verify 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_verify_accepts_home_manager_store_targets_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "/nix/store/example-dotfiles/$f" "$HOME/$f"
  done
  ln -s "/nix/store/example-dotfiles/bin/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$osrel" verify 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_verify_accepts_home_manager_store_targets_on_mac() {
  mock_uname Darwin
  mkdir -p "$DOTFILES_DIR"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "/nix/store/example-dotfiles/$f" "$HOME/$f"
  done
  ln -s "/nix/store/example-dotfiles/bin/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(verify 2>&1) || true

  assert_contains "$output" "All checks passed"
}

test_verify_accepts_home_manager_store_targets_on_arch() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$os_release" verify 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_verify_accepts_home_manager_store_targets_on_debian() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$hm_dir/bin/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(OS_RELEASE="$os_release" verify 2>&1) || true
  assert_contains "$output" "All checks passed"
}

test_verify_requires_nix_agent_tools_on_arch() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=arch\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"

  local bin_dir="$TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codex"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codebase-memory-mcp"
  chmod +x "$bin_dir/codex" "$bin_dir/codebase-memory-mcp"

  local output
  output=$(PATH="$bin_dir:$PATH" OS_RELEASE="$os_release" verify 2>&1) || true
  assert_contains "$output" "codex points to"
  assert_contains "$output" "codebase-memory-mcp points to"
  assert_contains "$output" "expected /nix/store"
}

test_verify_requires_nix_agent_tools_on_debian() {
  mock_uname Linux
  local os_release="$TEST_TMPDIR/os-release"
  printf 'ID=debian\n' > "$os_release"

  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"

  local bin_dir="$TEST_TMPDIR/bin"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codex"
  printf '#!/usr/bin/env bash\n' > "$bin_dir/codebase-memory-mcp"
  chmod +x "$bin_dir/codex" "$bin_dir/codebase-memory-mcp"

  local output
  output=$(PATH="$bin_dir:$PATH" OS_RELEASE="$os_release" verify 2>&1) || true
  assert_contains "$output" "codex points to"
  assert_contains "$output" "codebase-memory-mcp points to"
  assert_contains "$output" "expected /nix/store"
}

test_verify_accepts_nix_agent_tools_on_mac() {
  mock_uname Darwin
  local hm_dir="/nix/store/test-home-manager-files"
  local f
  for f in "${REQUIRED_SYMLINKS[@]}"; do
    ln -s "$hm_dir/$f" "$HOME/$f"
  done
  ln -s "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  printf 'source "$HOME/.zshrc.base"\n' > "$HOME/.zshrc"
  with_nix_agent_tools

  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "All checks passed"
}
