#!/usr/bin/env bash
# Pinned Codex and Obsidian Headless release update tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  setup_packages_test_env
}

teardown() {
  cleanup_test_env
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
