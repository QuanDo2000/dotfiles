#!/bin/bash
# Tests for individual package installation functions.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# install_font_debian
# ---------------------------------------------------------------------------

test_install_font_debian_dry_run() {
  DRY=true
  local output
  output=$(install_font_debian 2>&1)

  assert_contains "$output" "Installing Fira Code"
  assert_contains "$output" "Finished installing Fira Code"
}

test_install_font_debian_already_installed() {
  DRY=false
  mkdir -p "$HOME/.local/share/fonts"
  touch "$HOME/.local/share/fonts/FiraCodeNerdFont-Regular.ttf"

  local output
  output=$(install_font_debian 2>&1)

  assert_contains "$output" "Already installed font Fira Code"
}

# ---------------------------------------------------------------------------
# setup_lazygit (install mode)
# ---------------------------------------------------------------------------

test_setup_lazygit_dry_run() {
  DRY=true
  local output
  output=$(setup_lazygit 2>&1)

  assert_contains "$output" "lazygit"
  assert_contains "$output" "Finished lazygit"
}

test_setup_lazygit_already_installed() {
  DRY=false
  # Create a fake lazygit on PATH
  echo '#!/bin/bash' > "$HOME/.local/bin/lazygit"
  chmod +x "$HOME/.local/bin/lazygit"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_lazygit 2>&1)

  assert_contains "$output" "Already installed lazygit"
}

# ---------------------------------------------------------------------------
# setup_lazygit (update mode)
# ---------------------------------------------------------------------------

test_setup_lazygit_update_dry_run() {
  DRY=true
  local output
  output=$(setup_lazygit --update 2>&1)

  assert_contains "$output" "lazygit"
  assert_contains "$output" "Finished lazygit"
}

test_setup_lazygit_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/lazygit"
  chmod +x "$HOME/.local/bin/lazygit"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_lazygit --update 2>&1)

  # With --update, should NOT say "Already installed"
  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_zoxide (install mode)
# ---------------------------------------------------------------------------

test_setup_zoxide_dry_run() {
  DRY=true
  local output
  output=$(setup_zoxide 2>&1)

  assert_contains "$output" "zoxide"
  assert_contains "$output" "Finished zoxide"
}

test_setup_zoxide_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/zoxide"
  chmod +x "$HOME/.local/bin/zoxide"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_zoxide 2>&1)

  assert_contains "$output" "Already installed zoxide"
}

# ---------------------------------------------------------------------------
# setup_zoxide (update mode)
# ---------------------------------------------------------------------------

test_setup_zoxide_update_dry_run() {
  DRY=true
  local output
  output=$(setup_zoxide --update 2>&1)

  assert_contains "$output" "zoxide"
  assert_contains "$output" "Finished zoxide"
}

test_setup_zoxide_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/zoxide"
  chmod +x "$HOME/.local/bin/zoxide"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_zoxide --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_neovim (install mode)
# ---------------------------------------------------------------------------

test_setup_neovim_dry_run_linux() {
  mock_uname Linux
  DRY=true
  local output
  output=$(setup_neovim 2>&1)

  assert_contains "$output" "neovim"
  assert_contains "$output" "Finished neovim"
}

test_setup_neovim_already_installed() {
  mock_uname Linux
  DRY=false
  # nvim already on PATH (use the real one if available, otherwise fake it)
  if ! command -v nvim >/dev/null 2>&1; then
    echo '#!/bin/bash' > "$HOME/.local/bin/nvim"
    chmod +x "$HOME/.local/bin/nvim"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  local output
  output=$(setup_neovim 2>&1)

  assert_contains "$output" "Already installed neovim"
}

test_setup_neovim_skips_on_mac() {
  mock_uname Darwin
  DRY=false
  local output
  output=$(setup_neovim 2>&1)

  # Should return immediately with no output on Mac
  assert_equals "" "$output"
}

# ---------------------------------------------------------------------------
# setup_neovim (update mode)
# ---------------------------------------------------------------------------

test_setup_neovim_update_dry_run_linux() {
  mock_uname Linux
  DRY=true
  local output
  output=$(setup_neovim --update 2>&1)

  assert_contains "$output" "neovim"
  assert_contains "$output" "Finished neovim"
}

test_setup_neovim_update_does_not_skip() {
  mock_uname Linux
  DRY=true
  if ! command -v nvim >/dev/null 2>&1; then
    echo '#!/bin/bash' > "$HOME/.local/bin/nvim"
    chmod +x "$HOME/.local/bin/nvim"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  local output
  output=$(setup_neovim --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

test_setup_neovim_update_skips_on_mac() {
  mock_uname Darwin
  DRY=false
  local output
  output=$(setup_neovim --update 2>&1)

  assert_equals "" "$output"
}

# ---------------------------------------------------------------------------
# setup_fdfind
# ---------------------------------------------------------------------------

test_setup_fdfind_dry_run() {
  DRY=true
  local output
  output=$(setup_fdfind 2>&1)

  assert_contains "$output" "Ensuring 'fd' is available"
  assert_contains "$output" "Finished ensuring fd"
}

test_setup_fdfind_fd_on_path() {
  DRY=false
  # fd is available on macOS (installed via brew in this repo)
  if ! command -v fd >/dev/null 2>&1; then
    echo '#!/bin/bash' > "$HOME/.local/bin/fd"
    chmod +x "$HOME/.local/bin/fd"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  local output
  output=$(setup_fdfind 2>&1)

  assert_contains "$output" "'fd' already available on PATH"
}

test_setup_fdfind_neither_available() {
  DRY=false
  # Remove fd and fdfind from PATH by restricting to minimal dirs
  local orig_path="$PATH"
  export PATH="/usr/bin:/bin"

  # Make sure neither fd nor fdfind is in /usr/bin or /bin
  if command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; then
    export PATH="$orig_path"
    return  # Can't test — fd is in a system dir
  fi

  local output
  output=$(setup_fdfind 2>&1)

  assert_contains "$output" "fd not found on system"
  export PATH="$orig_path"
}
