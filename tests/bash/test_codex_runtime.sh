#!/usr/bin/env bash
# Codex runtime cleanup and package-update integration tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

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
  _sync_fff_nvim() { :; }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  local output
  output="$(<"$calls")"
  assert_equals "home-manager-switch" "$output"

  unset -f command _update_codex_release_package home-manager _sync_fff_nvim
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
  _sync_fff_nvim() { :; }
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
