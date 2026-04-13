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
# install_lazygit
# ---------------------------------------------------------------------------

test_install_lazygit_dry_run() {
  DRY=true
  local output
  output=$(install_lazygit 2>&1)

  assert_contains "$output" "Installing lazygit"
  assert_contains "$output" "Finished installing lazygit"
}

test_install_lazygit_already_installed() {
  DRY=false
  # Create a fake lazygit on PATH
  echo '#!/bin/bash' > "$HOME/.local/bin/lazygit"
  chmod +x "$HOME/.local/bin/lazygit"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(install_lazygit 2>&1)

  assert_contains "$output" "Already installed lazygit"
}

# ---------------------------------------------------------------------------
# install_zoxide
# ---------------------------------------------------------------------------

test_install_zoxide_dry_run() {
  DRY=true
  local output
  output=$(install_zoxide 2>&1)

  assert_contains "$output" "Installing zoxide"
  assert_contains "$output" "Finished installing zoxide"
}

test_install_zoxide_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/zoxide"
  chmod +x "$HOME/.local/bin/zoxide"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(install_zoxide 2>&1)

  assert_contains "$output" "Already installed zoxide"
}

# ---------------------------------------------------------------------------
# install_neovim
# ---------------------------------------------------------------------------

test_install_neovim_dry_run_linux() {
  mock_uname Linux
  DRY=true
  local output
  output=$(install_neovim 2>&1)

  assert_contains "$output" "Installing neovim"
  assert_contains "$output" "Finished installing neovim"
}

test_install_neovim_already_installed() {
  mock_uname Linux
  DRY=false
  # nvim already on PATH (use the real one if available, otherwise fake it)
  if ! command -v nvim >/dev/null 2>&1; then
    echo '#!/bin/bash' > "$HOME/.local/bin/nvim"
    chmod +x "$HOME/.local/bin/nvim"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  local output
  output=$(install_neovim 2>&1)

  assert_contains "$output" "Already installed neovim"
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
