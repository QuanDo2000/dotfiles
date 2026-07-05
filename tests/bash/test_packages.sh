#!/usr/bin/env bash
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
    echo '#!/usr/bin/env bash' > "$HOME/.local/bin/nvim"
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
    echo '#!/usr/bin/env bash' > "$HOME/.local/bin/nvim"
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
    echo '#!/usr/bin/env bash' > "$HOME/.local/bin/fd"
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
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/yay"
  chmod +x "$HOME/.local/bin/yay"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_yay 2>&1)

  assert_contains "$output" "Already installed yay"
}

# ---------------------------------------------------------------------------
# setup_lazygit (Debian GitHub-release installer)
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
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/lazygit"
  chmod +x "$HOME/.local/bin/lazygit"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_lazygit 2>&1)

  assert_contains "$output" "Already installed lazygit"
}

test_setup_lazygit_update_dry_run() {
  DRY=true
  local output
  output=$(setup_lazygit --update 2>&1)

  assert_contains "$output" "lazygit"
  assert_contains "$output" "Finished lazygit"
}

test_setup_lazygit_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/lazygit"
  chmod +x "$HOME/.local/bin/lazygit"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_lazygit --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_jj (Debian GitHub-release installer)
# ---------------------------------------------------------------------------

test_setup_jj_dry_run() {
  DRY=true
  local output
  output=$(setup_jj 2>&1)

  assert_contains "$output" "jj"
  assert_contains "$output" "Finished jj"
}

test_setup_jj_already_installed() {
  DRY=false
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/jj"
  chmod +x "$HOME/.local/bin/jj"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_jj 2>&1)

  assert_contains "$output" "Already installed jj"
}

test_setup_jj_update_dry_run() {
  DRY=true
  local output
  output=$(setup_jj --update 2>&1)

  assert_contains "$output" "jj"
  assert_contains "$output" "Finished jj"
}

test_setup_jj_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/jj"
  chmod +x "$HOME/.local/bin/jj"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_jj --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# setup_codex
# ---------------------------------------------------------------------------

test_setup_codex_dry_run() {
  DRY=true
  local output
  output=$(setup_codex 2>&1)

  assert_contains "$output" "codex"
  assert_contains "$output" "Finished codex"
}

test_setup_codex_already_installed() {
  DRY=false
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codex 2>&1)

  assert_contains "$output" "Already installed codex"
}

test_setup_codex_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codex --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_codebase_memory_mcp
# ---------------------------------------------------------------------------

test_setup_codebase_memory_mcp_dry_run() {
  DRY=true
  local output
  output=$(setup_codebase_memory_mcp 2>&1)

  assert_contains "$output" "codebase-memory-mcp"
  assert_contains "$output" "Finished codebase-memory-mcp"
}

test_setup_codebase_memory_mcp_already_installed() {
  DRY=false
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/codebase-memory-mcp"
  chmod +x "$HOME/.local/bin/codebase-memory-mcp"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codebase_memory_mcp 2>&1)

  assert_contains "$output" "Already installed codebase-memory-mcp"
}

test_setup_codebase_memory_mcp_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/codebase-memory-mcp"
  chmod +x "$HOME/.local/bin/codebase-memory-mcp"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_codebase_memory_mcp --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

test_codex_triple_linux() {
  mock_uname Linux
  local t
  t=$(_codex_triple)
  # arch varies by host; assert the OS half is the linux-musl target.
  assert_contains "$t" "unknown-linux-musl"
}

test_codex_triple_mac() {
  mock_uname Darwin
  local t
  t=$(_codex_triple)
  assert_contains "$t" "apple-darwin"
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
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/bun"
  chmod +x "$HOME/.local/bin/bun"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_bun 2>&1)

  assert_contains "$output" "Already installed bun"
}

test_setup_bun_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/bun"
  chmod +x "$HOME/.local/bin/bun"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_bun --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# setup_starship + package lists
# ---------------------------------------------------------------------------

test_setup_starship_dry_run() {
  DRY=true
  local output
  output=$(setup_starship 2>&1)

  assert_contains "$output" "starship"
  assert_contains "$output" "Finished starship"
}

test_setup_starship_already_installed() {
  DRY=false
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_starship 2>&1)

  assert_contains "$output" "Already installed starship"
}

test_setup_starship_update_does_not_skip() {
  DRY=true
  echo '#!/usr/bin/env bash' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_starship --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

test_arch_packages_include_starship() {
  assert_contains "${ARCH_PACKAGES[*]}" "starship"
}

test_mac_packages_include_starship() {
  assert_contains "${MAC_BREW_PACKAGES[*]}" "starship"
}

# ---------------------------------------------------------------------------
# NixOS package flow
# ---------------------------------------------------------------------------

test_install_nixos_dry_run() {
  DRY=true
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  _detect_nixos_machine_values() { printf 'alice\nmybox\nAsia/Tokyo\n24.11\n'; }

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "nixos-rebuild"
  assert_not_contains "$output" "neovim"

  unset -f _detect_nixos_machine_values
  unset NIXOS_MACHINE_FILE
}

test_update_nixos_dry_run() {
  DRY=true
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  _detect_nixos_machine_values() { printf 'alice\nmybox\nAsia/Tokyo\n24.11\n'; }

  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "nixos-rebuild"

  unset -f _detect_nixos_machine_values
  unset NIXOS_MACHINE_FILE
}

test_install_packages_dispatches_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=true

  local output
  output=$(OS_RELEASE="$osrel" install_packages 2>&1)

  assert_contains "$output" "NixOS"
}

test_set_zsh_default_skips_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=false

  local output
  output=$(OS_RELEASE="$osrel" set_zsh_default 2>&1)

  assert_contains "$output" "declaratively"
}

# ---------------------------------------------------------------------------
# NixOS machine.nix content + detection
# ---------------------------------------------------------------------------

test_nixos_machine_file_content() {
  local out
  out="$(_nixos_machine_file_content alice mybox Asia/Tokyo 24.11)"

  assert_contains "$out" 'username = "alice";'
  assert_contains "$out" 'hostName = "mybox";'
  assert_contains "$out" 'timeZone = "Asia/Tokyo";'
  assert_contains "$out" 'stateVersion = "24.11";'
}

test_detect_nixos_machine_values() {
  export SUDO_USER=""              # force the whoami branch
  whoami() { echo alice; }
  hostname() { echo mybox; }
  timedatectl() { echo "Asia/Tokyo"; }
  _nixos_version_string() { echo "24.11.20240115.abcdef (Vicuna)"; }

  local out u h t v
  out="$(_detect_nixos_machine_values)"
  { read -r u; read -r h; read -r t; read -r v; } <<< "$out"

  assert_equals "alice" "$u"
  assert_equals "mybox" "$h"
  assert_equals "Asia/Tokyo" "$t"
  assert_equals "24.11" "$v"

  unset -f whoami hostname timedatectl _nixos_version_string
  unset SUDO_USER
}

# ---------------------------------------------------------------------------
# _nixos_ensure_linked
# ---------------------------------------------------------------------------

test_nixos_ensure_linked_dry_would_write() {
  DRY=true
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"   # does not exist yet
  _detect_nixos_machine_values() { printf 'alice\nmybox\nAsia/Tokyo\n24.11\n'; }

  local out
  out="$(_nixos_ensure_linked 2>&1)"

  assert_contains "$out" "Would write"
  assert_contains "$out" "alice"
  assert_contains "$out" "mybox"
  # DRY must not create the file.
  if [ -f "$NIXOS_MACHINE_FILE" ]; then
    echo "  FAILED: DRY run wrote $NIXOS_MACHINE_FILE" >> "$ERROR_FILE"
  fi

  unset -f _detect_nixos_machine_values
  unset NIXOS_MACHINE_FILE
}

test_nixos_ensure_linked_skips_when_present() {
  DRY=true
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  echo '{ username = "bob"; }' > "$NIXOS_MACHINE_FILE"
  _detect_nixos_machine_values() { printf 'alice\nmybox\nAsia/Tokyo\n24.11\n'; }

  local out
  out="$(_nixos_ensure_linked 2>&1)"

  assert_contains "$out" "Using existing"
  if [[ "$out" == *"Would write"* ]]; then
    echo "  FAILED: regenerated an existing machine.nix" >> "$ERROR_FILE"
  fi

  unset -f _detect_nixos_machine_values
  unset NIXOS_MACHINE_FILE
}

test_nixos_ensure_linked_force_regenerates() {
  DRY=true
  FORCE=true
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  echo '{ username = "bob"; }' > "$NIXOS_MACHINE_FILE"   # already exists
  _detect_nixos_machine_values() { printf 'alice\nmybox\nAsia/Tokyo\n24.11\n'; }

  local out
  out="$(_nixos_ensure_linked 2>&1)"

  # FORCE re-detects even though the file is present.
  assert_contains "$out" "Would write"
  assert_contains "$out" "alice"
  if [[ "$out" == *"Using existing"* ]]; then
    echo "  FAILED: FORCE did not regenerate existing machine.nix" >> "$ERROR_FILE"
  fi

  unset -f _detect_nixos_machine_values
  unset NIXOS_MACHINE_FILE
}

test_detect_nixos_machine_values_fallbacks() {
  export SUDO_USER=""
  whoami() { echo ""; }            # empty → username fallback
  hostname() { return 1; }         # fail → hostName fallback
  timedatectl() { return 1; }      # fail → timeZone fallback
  _nixos_version_string() { echo ""; }   # empty → stateVersion fallback

  local out u h t v
  out="$(_detect_nixos_machine_values)"
  { read -r u; read -r h; read -r t; read -r v; } <<< "$out"

  assert_equals "nixos" "$u"
  assert_equals "nixos" "$h"
  assert_equals "UTC" "$t"
  assert_equals "24.11" "$v"

  unset -f whoami hostname timedatectl _nixos_version_string
  unset SUDO_USER
}
