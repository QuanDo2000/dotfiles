#!/usr/bin/env bash
# Codex runtime cleanup and package-update integration tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

_init_update_test_repo() {
  mkdir -p "$DOTFILES_DIR"
  git init -q "$DOTFILES_DIR"
  git -C "$DOTFILES_DIR" config user.email test@example.com
  git -C "$DOTFILES_DIR" config user.name Test
  : > "$DOTFILES_DIR/.test-root"
  git -C "$DOTFILES_DIR" add .test-root
  git -C "$DOTFILES_DIR" commit -qm initial
}

test_update_packages_refreshes_and_validates_all_pins_before_activation() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"

  _update_flake_inputs() { printf 'flake\n' >> "$calls"; }
  _update_all_dependency_pins() { printf 'pins\n' >> "$calls"; }
  _validate_dependency_update() { printf 'validate\n' >> "$calls"; }
  _approve_dependency_update() { printf 'approve\n' >> "$calls"; }
  _home_manager_switch() { printf 'activate:%s:%s\n' "$1" "${DOTFILE_FLAKE_REF:-}" >> "$calls"; }
  _cleanup_codex_runtime_after_update() { printf 'cleanup\n' >> "$calls"; }
  _update_pi_extensions() { printf 'extensions\n' >> "$calls"; }
  _sync_neovim() { printf 'fff\n' >> "$calls"; }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  assert_equals "$(printf 'flake\npins\nvalidate\napprove\nactivate:arch-server:path:%s\ncleanup\nextensions\nfff' "$DOTFILES_DIR")" "$(<"$calls")"

  unset -f _update_flake_inputs _update_all_dependency_pins _validate_dependency_update _approve_dependency_update \
    _home_manager_switch _cleanup_codex_runtime_after_update _update_pi_extensions _sync_neovim
}

test_update_ai_updates_only_ai_tools_and_configs() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
        codex) return 1 ;;
      esac
    fi
    builtin command "$@"
  }
  _update_codex_release_package() {
    printf 'codex-update\n' >> "$calls"
  }
  _update_pi_release_package() {
    printf 'pi-update\n' >> "$calls"
  }
  _validate_dependency_update() {
    printf 'validate\n' >> "$calls"
  }
  _approve_dependency_update() {
    printf 'approve\n' >> "$calls"
  }
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
  }
  _cleanup_codex_runtime_after_update() {
    printf 'codex-runtime-cleanup\n' >> "$calls"
  }
  pi() {
    printf 'pi %s\n' "$*" >> "$calls"
  }
  _sync_neovim() {
    printf 'fff.nvim\n' >> "$calls"
  }

  OS_RELEASE="$osrel" update_ai >/dev/null 2>&1

  assert_equals $'codex-update\npi-update\nvalidate\napprove\nhome-manager-switch\ncodex-runtime-cleanup\npi update --extensions' "$(<"$calls")"

  unset -f command _update_codex_release_package _update_pi_release_package _validate_dependency_update \
    _approve_dependency_update home-manager _cleanup_codex_runtime_after_update pi _sync_neovim
}

test_update_ai_validation_failure_stops_activation() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release" calls="$TEST_TMPDIR/ai-validation.log" status=0
  printf 'ID=arch\n' > "$osrel"
  _update_codex_release_package() { printf 'codex-update\n' >> "$calls"; }
  _update_pi_release_package() { printf 'pi-update\n' >> "$calls"; }
  _validate_dependency_update() { printf 'validate\n' >> "$calls"; return 1; }
  _home_manager_switch() { printf 'activate\n' >> "$calls"; }

  local output
  output="$(OS_RELEASE="$osrel" update_ai 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_equals $'codex-update\npi-update\nvalidate' "$(<"$calls")"
  unset -f _update_codex_release_package _update_pi_release_package _validate_dependency_update _home_manager_switch
}

test_update_ai_rechecks_validated_state_after_approval() {
  DRY=false
  mock_uname Linux
  local repo="$TEST_TMPDIR/ai-approval" old_dotfiles="$DOTFILES_DIR" osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/ai-approval.log" source_repo status=0 output
  printf 'ID=arch\n' > "$osrel"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'old\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  DOTFILES_DIR="$repo"
  source_repo="$repo"
  _refresh_ai_dependency_set() { printf 'validated\n' > "$DOTFILES_DIR/managed"; }
  _validate_dependency_update() { [[ "$(<"$DOTFILES_DIR/managed")" == validated ]]; }
  _approve_dependency_update() {
    printf 'tampered\n' > "$source_repo/managed"
    git -C "$source_repo" add managed
    git -C "$source_repo" commit -qm tampered
  }
  _home_manager_switch() { printf 'activate\n' >> "$calls"; }
  _cleanup_codex_runtime_after_update() { :; }
  _update_pi_extensions() { :; }

  output="$(OS_RELEASE="$osrel" update_ai 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_equals "" "$(cat "$calls" 2>/dev/null || true)"
  assert_contains "$output" "Pending dependency update changed"
  unset -f _refresh_ai_dependency_set _validate_dependency_update _approve_dependency_update \
    _home_manager_switch _cleanup_codex_runtime_after_update _update_pi_extensions
  DOTFILES_DIR="$old_dotfiles"
}

test_update_ai_nixos_rebuilds_without_updating_flake() {
  DRY=true
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  _update_codex_release_package() { :; }
  _update_pi_release_package() { :; }

  local output
  output=$(OS_RELEASE="$osrel" update_ai 2>&1)

  assert_contains "$output" "Would run: sudo nixos-rebuild switch --flake path:$DOTFILES_DIR#testhost"
  assert_not_contains "$output" "nix flake update"

  unset -f _update_codex_release_package _update_pi_release_package
}

test_update_ai_debian_and_mac_rebuild_without_updating_flake() {
  DRY=true
  _update_codex_release_package() { :; }
  _update_pi_release_package() { :; }

  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release" output
  printf 'ID=debian\n' > "$osrel"
  output="$(OS_RELEASE="$osrel" update_ai 2>&1)"
  assert_contains "$output" "home-manager switch --flake path:$DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "nix flake update"

  mock_uname Darwin
  output="$(update_ai 2>&1)"
  assert_contains "$output" "darwin-rebuild switch --flake path:$DOTFILES_DIR#mac"
  assert_not_contains "$output" "nix flake update"

  unset -f _update_codex_release_package _update_pi_release_package
}

test_update_packages_fails_unsupported_before_codex_update() {
  DRY=false
  mock_uname FreeBSD
  local calls="$TEST_TMPDIR/calls.log"
  : > "$calls"
  _update_codex_release_package() {
    printf 'codex-update\n' >> "$calls"
  }
  _update_pi_release_package() {
    printf 'pi-update\n' >> "$calls"
  }

  local output exit_code=0
  output=$(update_packages 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unsupported system: FreeBSD"
  assert_equals "" "$(<"$calls")"

  unset -f _update_codex_release_package _update_pi_release_package
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
  _update_all_dependency_pins() { :; }
  _validate_dependency_update() { :; }
  _update_pi_extensions() { :; }
  _sync_neovim() { :; }
}

test_update_packages_cleans_codex_runtime_when_version_changes() {
  _init_update_test_repo
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
  _init_update_test_repo
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
  assert_contains "$output" "nix flake update --flake"
  assert_contains "$output" "home-manager-switch"
  assert_not_contains "$output" "codex-stop"

  unset -f command codex home-manager rm
  unset MOCK_CODEX_CALLS MOCK_CODEX_VERSION
}

test_update_packages_cleans_codex_runtime_when_model_cache_is_stale() {
  _init_update_test_repo
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
