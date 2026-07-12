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

nix() {
  if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "username" ]]; then
    printf 'testuser\n'
    return 0
  fi
  if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "hostName" ]]; then
    printf 'testhost\n'
    return 0
  fi
  printf 'nix %s\n' "$*" >> "$calls"
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

  install_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo pacman -S --needed --noconfirm"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _install_lix _load_nix_profile
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
  assert_not_contains "$output" "sudo pacman"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_update_arch_bootstraps_home_manager_when_missing() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix) return 0 ;;
        home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }

  update_arch >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo pacman"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile
}

test_update_arch_dry_run_shows_home_manager_switch() {
  DRY=true

  local output
  output=$(update_arch 2>&1)

  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
}

test_debian_packages_are_bootstrap_only() {
  for pkg in curl git zsh procps file; do
    assert_contains "${DEBIAN_PACKAGES[*]}" "$pkg"
  done
  for pkg in build-essential xz-utils neovim starship nodejs tmux lazygit jujutsu ripgrep fd-find fzf fontconfig zoxide unzip; do
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

  install_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "sudo apt install -y"
  assert_contains "$output" "install-lix"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"
  assert_not_contains "$output" "neovim"

  unset -f command sudo _install_lix _load_nix_profile
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
  assert_not_contains "$output" "sudo apt"
  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile home-manager
}

test_update_debian_bootstraps_home_manager_when_missing() {
  DRY=false
  local calls="$TEST_TMPDIR/calls.log"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix) return 0 ;;
        home-manager) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  sudo() { printf 'sudo %s\n' "$*" >> "$calls"; }
  _load_nix_profile() { :; }

  update_debian >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_not_contains "$output" "sudo apt"
  assert_contains "$output" "nix run $DOTFILES_DIR#home-manager -- switch --flake $DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "@linux@linux"

  unset -f command sudo _load_nix_profile
}

test_update_debian_dry_run_shows_home_manager_switch() {
  DRY=true

  local output
  output=$(update_debian 2>&1)

  assert_contains "$output" "home-manager switch --flake $DOTFILES_DIR#testuser@linux"
}

test_latest_codex_release_tag_reads_github_redirect() {
  curl() {
    printf 'https://github.com/openai/codex/releases/tag/rust-v0.144.1'
  }

  local output
  output=$(_latest_codex_release_tag 2>&1)

  assert_equals "rust-v0.144.1" "$output"

  unset -f curl
}

test_update_codex_release_package_pins_latest_binary() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.nix" <<'EOF'
{
  version = "0.0.0";
  linuxHash = "sha256-old-linux";
  darwinHash = "sha256-old-darwin";
}
EOF
  local calls="$TEST_TMPDIR/codex-prefetch.log"
  curl() {
    printf 'https://github.com/openai/codex/releases/tag/rust-v0.144.1'
  }
  nix() {
    printf '%s\n' "$*" >> "$calls"
    case "$*" in
      *codex-package-x86_64-unknown-linux-musl.tar.gz*) printf '{"hash":"sha256-new-linux"}\n' ;;
      *openai_codex_cli_bin-0.144.1-py3-none-macosx_11_0_arm64.whl*) printf '{"hash":"sha256-new-darwin"}\n' ;;
      *) printf 'unexpected prefetch url: %s\n' "$*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }

  _update_codex_release_package >/dev/null 2>&1

  local output
  output="$(<"$DOTFILES_DIR/packages/codex-release.nix")"
  assert_contains "$output" 'version = "0.144.1";'
  assert_contains "$output" 'linuxHash = "sha256-new-linux";'
  assert_contains "$output" 'darwinHash = "sha256-new-darwin";'
  assert_contains "$(<"$calls")" "codex-package-x86_64-unknown-linux-musl.tar.gz"
  assert_contains "$(<"$calls")" "openai_codex_cli_bin-0.144.1-py3-none-macosx_11_0_arm64.whl"

  unset -f curl nix
}

test_update_codex_release_package_parses_spaced_prefetch_json() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.nix" <<'EOF'
{
  version = "0.0.0";
  linuxHash = "sha256-old-linux";
  darwinHash = "sha256-old-darwin";
}
EOF
  curl() {
    printf 'https://github.com/openai/codex/releases/tag/rust-v0.144.1'
  }
  nix() {
    printf '{ "hash": "sha256-new" }\n'
  }

  _update_codex_release_package >/dev/null 2>&1

  local output
  output="$(<"$DOTFILES_DIR/packages/codex-release.nix")"
  assert_contains "$output" 'linuxHash = "sha256-new";'
  assert_contains "$output" 'darwinHash = "sha256-new";'

  unset -f curl nix
}

test_update_codex_release_package_skips_current_version() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.nix" <<'EOF'
{
  version = "0.144.1";
  hash = "sha256-current";
}
EOF
  local calls="$TEST_TMPDIR/calls.log"
  _latest_codex_release_tag() {
    printf 'latest\n' >> "$calls"
    printf 'rust-v0.144.1\n'
  }
  _ensure_nix() {
    printf 'ensure-nix\n' >> "$calls"
  }
  _prefetch_codex_release_hash() {
    printf 'prefetch\n' >> "$calls"
    printf 'sha256-new\n'
  }
  _write_codex_release_package() {
    printf 'write\n' >> "$calls"
  }

  local output
  output=$(_update_codex_release_package 2>&1)

  assert_contains "$output" "Codex package already at rust-v0.144.1"
  assert_equals "latest" "$(<"$calls")"

  unset -f _latest_codex_release_tag _ensure_nix _prefetch_codex_release_hash _write_codex_release_package
}

test_update_codex_release_package_dry_run_skips_network() {
  DRY=true
  curl() {
    echo "curl should not run in dry-run mode" >> "$ERROR_FILE"
    return 1
  }

  local output
  output=$(_update_codex_release_package 2>&1)

  assert_contains "$output" "Would update Codex package from the latest GitHub release"

  unset -f curl
}

test_update_obsidian_headless_package_pins_latest_release() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/obsidian-headless.nix" <<'EOF'
{
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha256-old-src";
  };

  npmDepsHash = "sha256-old-deps";
}
EOF
  printf '{"old":true}\n' > "$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"

  curl() {
    case "$*" in
      *registry.npmjs.org/obsidian-headless/latest*) printf '{"version":"0.0.13"}' ;;
      *obsidian-headless-0.0.13.tgz*) printf '{"new":true}\n' > "$4" ;;
      *) echo "unexpected curl: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  nix() {
    case "$*" in
      *prefetch-file*obsidian-headless-0.0.13.tgz*) printf '{ "hash": "sha256-new-src" }\n' ;;
      *prefetch-npm-deps*) printf 'sha256-new-deps\n' ;;
      *) echo "unexpected nix: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  tar() {
    assert_contains "$*" "package/package-lock.json"
    printf '{"new":true}\n'
  }

  _update_obsidian_headless_package >/dev/null 2>&1

  local package_text
  package_text="$(<"$DOTFILES_DIR/packages/obsidian-headless.nix")"
  assert_contains "$package_text" 'version = "0.0.13";'
  assert_contains "$package_text" 'hash = "sha256-new-src";'
  assert_contains "$package_text" 'npmDepsHash = "sha256-new-deps";'
  assert_equals '{"new":true}' "$(<"$DOTFILES_DIR/packages/obsidian-headless-package-lock.json")"

  unset -f curl nix tar
}

test_update_obsidian_headless_package_keeps_old_files_when_deps_prefetch_fails() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/obsidian-headless.nix" <<'EOF'
{
  buildNpmPackage,
  fetchurl,
}:

buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha256-old-src";
  };

  npmDepsHash = "sha256-old-deps";
}
EOF
  printf '{"old":true}\n' > "$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"

  curl() {
    case "$*" in
      *registry.npmjs.org/obsidian-headless/latest*) printf '{"version":"0.0.13"}' ;;
      *obsidian-headless-0.0.13.tgz*) printf '{"new":true}\n' > "$4" ;;
      *) echo "unexpected curl: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  nix() {
    case "$*" in
      *prefetch-file*obsidian-headless-0.0.13.tgz*) printf '{ "hash": "sha256-new-src" }\n' ;;
      *prefetch-npm-deps*) return 1 ;;
      *) echo "unexpected nix: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  tar() {
    printf '{"new":true}\n'
  }

  local output exit_code package_text
  exit_code=0
  output=$(_update_obsidian_headless_package 2>&1) || exit_code=$?
  package_text="$(<"$DOTFILES_DIR/packages/obsidian-headless.nix")"

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to prefetch Obsidian Headless npm deps"
  assert_contains "$package_text" 'version = "0.0.0";'
  assert_contains "$package_text" 'hash = "sha256-old-src";'
  assert_contains "$package_text" 'npmDepsHash = "sha256-old-deps";'
  assert_equals '{"old":true}' "$(<"$DOTFILES_DIR/packages/obsidian-headless-package-lock.json")"

  unset -f curl nix tar
}

test_update_obsidian_headless_package_dry_run_skips_network() {
  DRY=true
  curl() {
    echo "curl should not run in dry-run mode" >> "$ERROR_FILE"
    return 1
  }

  local output
  output=$(_update_obsidian_headless_package 2>&1)

  assert_contains "$output" "Would update Obsidian Headless package from the latest npm release"

  unset -f curl
}

test_update_packages_does_not_update_codex_release_pin() {
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.nix" <<'EOF'
{
  version = "0.0.0";
  hash = "sha256-old";
}
EOF

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  _update_codex_release_package() {
    printf 'codex-update\n' >> "$calls"
  }
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
  }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_equals "home-manager-switch" "$output"

  unset -f command _update_codex_release_package home-manager
}

test_update_packages_fails_unsupported_before_codex_update() {
  DRY=false
  mock_uname FreeBSD
  local calls="$TEST_TMPDIR/calls.log"
  : > "$calls"
  _update_codex_release_package() {
    printf 'codex-update\n' >> "$calls"
  }

  local output exit_code=0
  output=$(update_packages 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unsupported system: FreeBSD"
  assert_equals "" "$(<"$calls")"

  unset -f _update_codex_release_package
}

test_codex_model_cache_version_reads_multiline_json() {
  mkdir -p "$HOME/.codex"
  printf '{\n  "client_version":\n    "0.144.1"\n}\n' > "$HOME/.codex/models_cache.json"

  assert_equals "0.144.1" "$(_codex_model_cache_version)"
}

test_cleanup_stale_codex_runtime_uses_codex_home() {
  CODEX_HOME="$TEST_TMPDIR/codex-home"
  local calls="$TEST_TMPDIR/calls.log"
  codex() { :; }
  rm() { printf 'rm %s\n' "$*" > "$calls"; }

  _cleanup_stale_codex_runtime

  assert_contains "$(<"$calls")" "$CODEX_HOME/models_cache.json"
  assert_contains "$(<"$calls")" "$CODEX_HOME/app-server-control/app-server-control.sock"
  unset -f codex rm
  unset CODEX_HOME
}

_mock_codex_update_runtime() {
  MOCK_CODEX_CALLS="$1"
  MOCK_CODEX_VERSION="$2"
  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        codex|nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  codex() {
    case "$*" in
      "--version") printf '%s\n' "$MOCK_CODEX_VERSION" ;;
      "app-server daemon stop") printf 'codex-stop\n' >> "$MOCK_CODEX_CALLS" ;;
    esac
  }
  rm() {
    printf 'rm %s\n' "$*" >> "$MOCK_CODEX_CALLS"
  }
}

test_update_packages_cleans_codex_runtime_when_version_changes() {
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"
  _mock_codex_update_runtime "$calls" "codex-cli 0.142.3"
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
    MOCK_CODEX_VERSION="codex-cli 0.144.1"
  }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "home-manager-switch"
  assert_contains "$output" "codex-stop"
  assert_contains "$output" "$HOME/.codex/models_cache.json"
  assert_contains "$output" "$HOME/.codex/app-server-control/app-server-control.sock"

  unset -f command codex home-manager rm
  unset MOCK_CODEX_CALLS MOCK_CODEX_VERSION
}

test_update_packages_skips_codex_runtime_cleanup_when_version_is_same() {
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"
  _mock_codex_update_runtime "$calls" "codex-cli 0.144.1"
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
  }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_equals "home-manager-switch" "$output"

  unset -f command codex home-manager rm
  unset MOCK_CODEX_CALLS MOCK_CODEX_VERSION
}

test_update_packages_cleans_codex_runtime_when_model_cache_is_stale() {
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"
  : > "$calls"
  mkdir -p "$HOME/.codex"
  printf '{"client_version":"0.142.3"}\n' > "$HOME/.codex/models_cache.json"
  _mock_codex_update_runtime "$calls" "codex-cli 0.144.1"
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
  }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "home-manager-switch"
  assert_contains "$output" "codex-stop"
  assert_contains "$output" "$HOME/.codex/models_cache.json"

  unset -f command codex home-manager rm
  unset MOCK_CODEX_CALLS MOCK_CODEX_VERSION
}

test_update_packages_dry_run_preserves_stale_codex_runtime() {
  DRY=true
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"
  : > "$calls"
  mkdir -p "$HOME/.codex"
  printf '{"client_version":"0.142.3"}\n' > "$HOME/.codex/models_cache.json"
  _mock_codex_update_runtime "$calls" "codex-cli 0.144.1"

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  assert_equals "" "$(<"$calls")"
  assert_file_exists "$HOME/.codex/models_cache.json"

  unset -f command codex rm
  unset MOCK_CODEX_CALLS MOCK_CODEX_VERSION
}

# ---------------------------------------------------------------------------
# NixOS package flow
# ---------------------------------------------------------------------------

test_install_nixos_dry_run() {
  DRY=true

  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "neovim"
}

test_update_nixos_dry_run() {
  DRY=true

  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_contains "$output" "sudo nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#testhost"
}

test_nixos_flake_target_reads_host_config_when_nix_is_missing() {
  mkdir -p "$DOTFILES_DIR/config"
  cat > "$DOTFILES_DIR/config/host.nix" <<'EOF'
{
  username = "testuser";
  hostName = "fallbackhost";
}
EOF
  nix() { return 127; }

  local output
  output=$(_nixos_flake_target 2>&1)

  assert_equals "$DOTFILES_DIR#fallbackhost" "$output"
  unset -f nix
}

test_nixos_flake_target_fails_when_hostname_missing() {
  nix() {
    if [[ "${1:-}" == "eval" && "${2:-}" == "--raw" && "${3:-}" == "--file" && "${4:-}" == "$DOTFILES_DIR/config/host.nix" && "${5:-}" == "hostName" ]]; then
      return 1
    fi
  }

  local output exit_code=0
  output=$(_nixos_flake_target 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to resolve NixOS host name"
  assert_not_contains "$output" "$DOTFILES_DIR#"

  unset -f nix
}

test_nix_managed_lazy_nvim_is_excluded_from_lazy_updates() {
  local config
  config="$(<"$REPO_DIR/config/shared/config/nvim/lua/config/lazy.lua")"

  assert_contains "$config" '{ "folke/lazy.nvim", enabled = false }'
}

test_home_manager_forces_jj_config_takeover() {
  local config
  config="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$config" '"${homeDir}/.config/jj/config.toml".force = true;'
}

test_install_nixos_uses_flake_switch() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  install_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--impure"

  unset -f sudo
}

test_update_nixos_uses_flake_switch_upgrade() {
  local calls="$TEST_TMPDIR/sudo.log"
  sudo() { printf '%s\n' "$*" >> "$calls"; }

  update_nixos >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_contains "$output" "nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#testhost"
  assert_not_contains "$output" "--impure"

  unset -f sudo
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
