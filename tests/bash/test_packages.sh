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

# ---------------------------------------------------------------------------
# setup_yay
# ---------------------------------------------------------------------------

test_setup_yay_dry_run() {
  DRY=true
  local output
  output=$(setup_yay 2>&1)

  assert_contains "$output" "yay"
  assert_contains "$output" "Finished yay"
}

test_setup_yay_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/yay"
  chmod +x "$HOME/.local/bin/yay"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_yay 2>&1)

  assert_contains "$output" "Already installed yay"
}

# ---------------------------------------------------------------------------
# setup_brew_linux
# ---------------------------------------------------------------------------

test_setup_brew_linux_dry_run() {
  DRY=true
  local output
  output=$(setup_brew_linux 2>&1)

  assert_contains "$output" "Homebrew"
  assert_contains "$output" "Finished Homebrew"
}

test_setup_brew_linux_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/brew"
  chmod +x "$HOME/.local/bin/brew"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_brew_linux 2>&1)

  assert_contains "$output" "Already installed Homebrew"
}

test_setup_brew_linux_update_dry_run() {
  DRY=true
  local output
  output=$(setup_brew_linux --update 2>&1)

  assert_contains "$output" "Homebrew"
  assert_contains "$output" "Finished Homebrew"
}

test_setup_brew_linux_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/brew"
  chmod +x "$HOME/.local/bin/brew"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_brew_linux --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_pwsh
# ---------------------------------------------------------------------------

test_setup_pwsh_skips_on_mac() {
  detect_platform() { echo "mac"; }
  DRY=false
  local output
  output=$(setup_pwsh 2>&1)

  # Mac path uses brew casks via install_mac; setup_pwsh itself is a no-op.
  assert_equals "" "$output"
}

test_setup_pwsh_dry_run_debian() {
  detect_platform() { echo "debian"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}

test_setup_pwsh_already_installed() {
  detect_platform() { echo "debian"; }
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/pwsh"
  chmod +x "$HOME/.local/bin/pwsh"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "Already installed pwsh"
}

test_setup_pwsh_update_dry_run() {
  detect_platform() { echo "debian"; }
  DRY=true
  local output
  output=$(setup_pwsh --update 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}

test_setup_pwsh_update_does_not_skip() {
  detect_platform() { echo "debian"; }
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/pwsh"
  chmod +x "$HOME/.local/bin/pwsh"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_pwsh --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

test_setup_pwsh_dry_run_arch() {
  detect_platform() { echo "arch"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}

# ---------------------------------------------------------------------------
# setup_claude_code
# ---------------------------------------------------------------------------

test_setup_claude_code_dry_run() {
  DRY=true
  local output
  output=$(setup_claude_code 2>&1)

  assert_contains "$output" "Claude Code"
  assert_contains "$output" "Finished Claude Code"
}

test_setup_claude_code_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_claude_code 2>&1)

  assert_contains "$output" "Already installed Claude Code"
}

test_setup_claude_code_update_dry_run() {
  DRY=true
  local output
  output=$(setup_claude_code --update 2>&1)

  assert_contains "$output" "Claude Code"
  assert_contains "$output" "Finished Claude Code"
}

test_setup_claude_code_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_claude_code --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_opencode
# ---------------------------------------------------------------------------

test_setup_opencode_dry_run() {
  DRY=true
  local output
  output=$(setup_opencode 2>&1)

  assert_contains "$output" "OpenCode"
  assert_contains "$output" "Finished OpenCode"
}

test_setup_opencode_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/opencode"
  chmod +x "$HOME/.local/bin/opencode"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_opencode 2>&1)

  assert_contains "$output" "Already installed OpenCode"
}

test_setup_opencode_update_dry_run() {
  DRY=true
  local output
  output=$(setup_opencode --update 2>&1)

  assert_contains "$output" "OpenCode"
  assert_contains "$output" "Finished OpenCode"
}

test_setup_opencode_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/opencode"
  chmod +x "$HOME/.local/bin/opencode"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_opencode --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_bun
# ---------------------------------------------------------------------------

test_setup_bun_dry_run() {
  DRY=true
  local output
  output=$(setup_bun 2>&1)

  assert_contains "$output" "bun"
  assert_contains "$output" "Finished bun"
}

test_setup_bun_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/bun"
  chmod +x "$HOME/.local/bin/bun"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_bun 2>&1)

  assert_contains "$output" "Already installed bun"
}

test_setup_bun_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/bun"
  chmod +x "$HOME/.local/bin/bun"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_bun --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_codex
# ---------------------------------------------------------------------------

test_setup_codex_dry_run() {
  DRY=true
  local output
  output=$(setup_codex 2>&1)

  assert_contains "$output" "Codex"
  assert_contains "$output" "Finished Codex"
}

test_setup_codex_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codex 2>&1)

  assert_contains "$output" "Already installed Codex"
}

test_setup_codex_update_dry_run() {
  DRY=true
  local output
  output=$(setup_codex --update 2>&1)

  assert_contains "$output" "Codex"
  assert_contains "$output" "Finished Codex"
}

test_setup_codex_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codex --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}
