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
# Linux package flows
# ---------------------------------------------------------------------------

test_arch_packages_are_bootstrap_only() {
  assert_contains "${ARCH_PACKAGES[*]}" "base-devel"
  assert_contains "${ARCH_PACKAGES[*]}" "curl"
  assert_contains "${ARCH_PACKAGES[*]}" "git"
  assert_contains "${ARCH_PACKAGES[*]}" "zsh"
  for pkg in neovim starship nodejs tmux lazygit jujutsu ripgrep fd fzf; do
    if [[ " ${ARCH_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Arch pacman packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_install_arch_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }
  nix() { printf 'nix %s\n' "$*" >> "$calls"; }

  install_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -S --needed --noconfirm"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#quando@linux"
  assert_not_contains "$output" "home-manager/master"

  unset -f command sudo _install_lix _load_nix_profile nix
}

test_install_arch_leaves_agent_tools_to_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { :; }
  _load_nix_profile() { :; }
  home-manager() { :; }
  setup_codex() { printf 'setup_codex %s\n' "$*" >> "$calls"; }
  setup_codebase_memory_mcp() { printf 'setup_codebase_memory_mcp %s\n' "$*" >> "$calls"; }

  install_arch >/dev/null 2>&1
  update_arch >/dev/null 2>&1

  if [[ -e "$calls" ]]; then
    echo "  FAILED: Arch should leave codex/codebase-memory-mcp to Home Manager: $(cat "$calls")" >> "$ERROR_FILE"
  fi

  unset -f command sudo _load_nix_profile home-manager setup_codex setup_codebase_memory_mcp
}

test_install_arch_removes_old_repo_ghostty_dir_symlink_before_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  mkdir -p "$DOTFILES_DIR/config/unix/config/ghostty" "$HOME/.config"
  echo "ghostty" > "$DOTFILES_DIR/config/unix/config/ghostty/config"
  ln -s "$DOTFILES_DIR/config/unix/config/ghostty" "$HOME/.config/ghostty"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() {
    if [ -L "$HOME/.config/ghostty" ]; then
      echo "ghostty symlink still present before home-manager" >> "$ERROR_FILE"
    fi
    printf 'home-manager %s\n' "$*" >> "$calls"
  }

  install_arch >/dev/null 2>&1

  if [ -L "$HOME/.config/ghostty" ]; then
    echo "  FAILED: old repo-linked ~/.config/ghostty should be removed before Home Manager" >> "$ERROR_FILE"
  fi
  assert_file_exists "$DOTFILES_DIR/config/unix/config/ghostty/config"

  unset -f command sudo _load_nix_profile home-manager
}

test_install_arch_removes_old_agent_tool_installs_before_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/codex-v1" \
    "$HOME/.bun/bin" "$HOME/.bun/install/global/node_modules/@openai/codex"
  touch "$HOME/.local/codex-v1/codex" \
    "$HOME/.local/bin/codebase-memory-mcp" \
    "$HOME/.bun/install/global/node_modules/@openai/codex/package.json"
  ln -s "$HOME/.local/codex-v1/codex" "$HOME/.local/bin/codex"
  ln -s "../install/global/node_modules/@openai/codex/bin/codex.js" "$HOME/.bun/bin/codex"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { :; }
  _load_nix_profile() { :; }
  home-manager() {
    for path in \
      "$HOME/.local/bin/codebase-memory-mcp" \
      "$HOME/.local/bin/codex" \
      "$HOME/.local/codex-v1" \
      "$HOME/.bun/bin/codex" \
      "$HOME/.bun/install/global/node_modules/@openai/codex"; do
      if [[ -e "$path" || -L "$path" ]]; then
        echo "old agent tool install still present before home-manager: $path" >> "$ERROR_FILE"
      fi
    done
    printf 'home-manager %s\n' "$*" >> "$calls"
  }

  install_arch >/dev/null 2>&1

  assert_contains "$(<"$calls")" "home-manager switch --flake $DOTFILES_DIR#quando@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_update_arch_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -Syu --noconfirm"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#quando@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_debian_packages_are_bootstrap_only() {
  for pkg in curl git xz-utils zsh procps file; do
    assert_contains "${DEBIAN_PACKAGES[*]}" "$pkg"
  done
  for pkg in build-essential neovim starship nodejs tmux lazygit jujutsu ripgrep fd-find fzf fontconfig zoxide unzip; do
    if [[ " ${DEBIAN_PACKAGES[*]} " == *" $pkg "* ]]; then
      echo "  FAILED: Debian apt packages should not install $pkg; Home Manager owns user tools" >> "$ERROR_FILE"
    fi
  done
}

test_install_debian_bootstraps_nix_and_switches_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _install_lix() { printf '%s\n' "install-lix" >> "$calls"; }
  _load_nix_profile() { :; }
  nix() { printf 'nix %s\n' "$*" >> "$calls"; }

  install_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt install -y"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#quando@linux"
  assert_not_contains "$output" "neovim"

  unset -f command sudo _install_lix _load_nix_profile nix
}

test_update_debian_uses_existing_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }
  home-manager() { printf 'home-manager %s\n' "$*" >> "$calls"; }

  update_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt update -y"
  assert_contains "$output" "sudo apt upgrade -y"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#quando@linux"

  unset -f command sudo _load_nix_profile home-manager
}

# ---------------------------------------------------------------------------
# NixOS package flow
# ---------------------------------------------------------------------------

test_install_nixos_dry_run() {
  DRY=true

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#nixos"
  assert_not_contains "$output" "neovim"
}

test_update_nixos_dry_run() {
  DRY=true

  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#nixos"
}

test_install_nixos_uses_flake_switch() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }
  setup_codebase_memory_mcp() { :; }

  install_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --flake $DOTFILES_DIR#nixos"
  assert_not_contains "$output" "--impure"

  unset -f sudo
  unset -f setup_codebase_memory_mcp
}

test_nixos_leaves_codebase_memory_to_home_manager() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  sudo() { :; }
  setup_codebase_memory_mcp() { printf 'setup_codebase_memory_mcp %s\n' "$*" >> "$calls"; }

  install_nixos >/dev/null 2>&1
  update_nixos >/dev/null 2>&1

  if [[ -e "$calls" ]]; then
    echo "  FAILED: NixOS should leave codebase-memory-mcp to Home Manager: $(cat "$calls")" >> "$ERROR_FILE"
  fi

  unset -f sudo setup_codebase_memory_mcp
}

test_install_nixos_cleans_old_plugin_dirs_before_switch() {
  local zsh_plugin="$HOME/.local/share/zsh/plugins/zsh-autosuggestions"
  local tmux_plugin="$HOME/.tmux/plugins/tmux-yank"
  mkdir -p "$zsh_plugin/.git" "$zsh_plugin.before-home-manager/zsh-autosuggestions" \
    "$tmux_plugin/.git" "$tmux_plugin.before-home-manager/tmux-yank"
  sudo() { :; }
  setup_codebase_memory_mcp() { :; }

  install_nixos >/dev/null 2>&1

  if [ -e "$zsh_plugin" ] || [ -e "$zsh_plugin.before-home-manager" ]; then
    echo "  FAILED: old zsh plugin dirs should be removed before nixos-rebuild" >> "$ERROR_FILE"
  fi
  if [ -e "$tmux_plugin" ] || [ -e "$tmux_plugin.before-home-manager" ]; then
    echo "  FAILED: old tmux plugin dirs should be removed before nixos-rebuild" >> "$ERROR_FILE"
  fi

  unset -f sudo setup_codebase_memory_mcp
}

test_update_nixos_uses_flake_switch_upgrade() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }
  setup_codebase_memory_mcp() { :; }

  update_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#nixos"
  assert_not_contains "$output" "--impure"

  unset -f sudo
  unset -f setup_codebase_memory_mcp
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

test_install_nixos_does_not_write_machine_file() {
  DRY=false
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  sudo() { :; }
  setup_codebase_memory_mcp() { :; }

  install_nixos >/dev/null 2>&1

  if [ -e "$NIXOS_MACHINE_FILE" ]; then
    echo "  FAILED: install_nixos should not write $NIXOS_MACHINE_FILE" >> "$ERROR_FILE"
  fi

  unset -f sudo setup_codebase_memory_mcp
  unset NIXOS_MACHINE_FILE
}

test_update_nixos_does_not_write_machine_file() {
  DRY=false
  export NIXOS_MACHINE_FILE="$TEST_TMPDIR/machine.nix"
  sudo() { :; }
  setup_codebase_memory_mcp() { :; }

  update_nixos >/dev/null 2>&1

  if [ -e "$NIXOS_MACHINE_FILE" ]; then
    echo "  FAILED: update_nixos should not write $NIXOS_MACHINE_FILE" >> "$ERROR_FILE"
  fi

  unset -f sudo setup_codebase_memory_mcp
  unset NIXOS_MACHINE_FILE
}
