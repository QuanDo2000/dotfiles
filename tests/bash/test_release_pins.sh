#!/usr/bin/env bash
# Pinned Pi, Codex, and Obsidian Headless release update tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

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
  cat > "$DOTFILES_DIR/packages/codex-release.json" <<'EOF'
{"version":"0.0.0","linuxHash":"sha256-old-linux","darwinHash":"sha256-old-darwin","windows":{"x86_64":"old-x64","aarch64":"old-arm64"}}
EOF
  local calls="$TEST_TMPDIR/codex-prefetch.log"
  curl() {
    case "$*" in
      *releases/latest*) printf 'https://github.com/openai/codex/releases/tag/rust-v0.144.1' ;;
      *api.github.com*) cat <<'EOF'
{"assets":[{"name":"codex-package-x86_64-pc-windows-msvc.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"name":"codex-package-aarch64-pc-windows-msvc.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
EOF
        ;;
      *) return 1 ;;
    esac
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
  output="$(<"$DOTFILES_DIR/packages/codex-release.json")"
  assert_equals "0.144.1" "$(jq -r .version <<< "$output")"
  assert_equals "sha256-new-linux" "$(jq -r .linuxHash <<< "$output")"
  assert_equals "sha256-new-darwin" "$(jq -r .darwinHash <<< "$output")"
  assert_equals "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(jq -r .windows.x86_64 <<< "$output")"
  assert_equals "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$(jq -r .windows.aarch64 <<< "$output")"
  assert_contains "$(<"$calls")" "codex-package-x86_64-unknown-linux-musl.tar.gz"
  assert_contains "$(<"$calls")" "openai_codex_cli_bin-0.144.1-py3-none-macosx_11_0_arm64.whl"

  unset -f curl nix
}

test_update_codex_release_package_keeps_existing_pins_when_windows_metadata_fails() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  local pins="$DOTFILES_DIR/packages/codex-release.json"
  local original='{"version":"0.0.0","linuxHash":"sha256-old-linux","darwinHash":"sha256-old-darwin","windows":{"x86_64":"old-x64","aarch64":"old-arm64"}}'
  printf '%s\n' "$original" > "$pins"
  _latest_codex_release_tag() { printf 'rust-v0.144.1\n'; }
  _ensure_nix() { :; }
  _prefetch_codex_release_hash() { printf 'sha256-new\n'; }
  _codex_windows_release_hashes() { fail 'Invalid Codex Windows ARM64 checksum'; }

  local output exit_code
  exit_code=0
  output=$(_update_codex_release_package 2>&1) || exit_code=$?

  assert_equals '1' "$exit_code"
  assert_contains "$output" 'Failed to resolve Codex Windows checksums'
  assert_equals "$original" "$(<"$pins")"

  unset -f _latest_codex_release_tag _ensure_nix _prefetch_codex_release_hash _codex_windows_release_hashes
}

test_update_codex_release_package_parses_spaced_prefetch_json() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.json" <<'EOF'
{"version":"0.0.0","linuxHash":"sha256-old-linux","darwinHash":"sha256-old-darwin","windows":{"x86_64":"old-x64","aarch64":"old-arm64"}}
EOF
  curl() {
    case "$*" in
      *releases/latest*) printf 'https://github.com/openai/codex/releases/tag/rust-v0.144.1' ;;
      *api.github.com*) cat <<'EOF'
{"assets":[{"name":"codex-package-x86_64-pc-windows-msvc.tar.gz","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"name":"codex-package-aarch64-pc-windows-msvc.tar.gz","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}
EOF
        ;;
      *) return 1 ;;
    esac
  }
  nix() {
    printf '{ "hash": "sha256-new" }\n'
  }

  _update_codex_release_package >/dev/null 2>&1

  local output
  output="$(<"$DOTFILES_DIR/packages/codex-release.json")"
  assert_equals "sha256-new" "$(jq -r .linuxHash <<< "$output")"
  assert_equals "sha256-new" "$(jq -r .darwinHash <<< "$output")"

  unset -f curl nix
}

test_update_codex_release_package_skips_current_version() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/codex-release.json" <<'EOF'
{"version":"0.144.1","linuxHash":"sha256-current","darwinHash":"sha256-current","windows":{"x86_64":"current","aarch64":"current"}}
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

test_release_file_pair_rolls_back_when_second_replace_fails() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local staged_package="$TEST_TMPDIR/package.nix.staged"
  local staged_lock="$TEST_TMPDIR/package-lock.json.staged"
  printf 'old package\n' > "$package_file"
  printf 'old lock\n' > "$lock_file"
  printf 'new package\n' > "$staged_package"
  printf 'new lock\n' > "$staged_lock"
  mv() {
    if [[ "${2:-}" == "$lock_file" ]]; then
      return 1
    fi
    command mv "$@"
  }

  local output exit_code=0
  output=$(_install_release_file_pair "$staged_package" "$package_file" "$staged_lock" "$lock_file" "test release" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to install test release files"
  assert_equals "old package" "$(<"$package_file")"
  assert_equals "old lock" "$(<"$lock_file")"
  if [[ -e "$staged_package" || -e "$staged_lock" ]]; then
    echo "  FAILED: staged release files should be cleaned after rollback" >> "$ERROR_FILE"
  fi

  unset -f mv
}

test_update_pi_release_package_pins_latest_release() {
  DRY=false
  mkdir -p "$DOTFILES_DIR/packages"
  cat > "$DOTFILES_DIR/packages/pi-agent.nix" <<'EOF'
{
  version = "0.0.0";
  hash = "sha256-old-src";
  npmDepsHash = "sha256-old-deps";
}
EOF
  printf '{"old":true}\n' > "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  chmod 644 "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"

  curl() {
    case "$*" in
      *pi-coding-agent/latest*) printf '{"version":"0.80.7"}' ;;
      *pi-coding-agent-0.80.7.tgz*) printf 'tarball\n' > "$4" ;;
      *pi-agent-core/0.80.7*) printf '{"dist":{"integrity":"sha512-core"}}' ;;
      *pi-ai/0.80.7*) printf '{"dist":{"integrity":"sha512-ai"}}' ;;
      *pi-tui/0.80.7*) printf '{"dist":{"integrity":"sha512-tui"}}' ;;
      *) echo "unexpected curl: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  tar() {
    cat <<'EOF'
{"packages":{"node_modules/@earendil-works/pi-agent-core":{"version":"0.80.7","resolved":"core"},"node_modules/@earendil-works/pi-ai":{"version":"0.80.7","resolved":"ai"},"node_modules/@earendil-works/pi-tui":{"version":"0.80.7","resolved":"tui"}}}
EOF
  }
  nix() {
    case "$*" in
      *prefetch-file*pi-coding-agent-0.80.7.tgz*) printf '{"hash":"sha256-new-src"}\n' ;;
      *prefetch-npm-deps*) printf 'sha256-new-deps\n' ;;
      *) echo "unexpected nix: $*" >> "$ERROR_FILE"; return 1 ;;
    esac
  }
  nix-instantiate() { return 0; }

  _update_pi_release_package >/dev/null 2>&1

  local package_text lock_text
  package_text="$(<"$DOTFILES_DIR/packages/pi-agent.nix")"
  lock_text="$(<"$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json")"
  assert_contains "$package_text" 'version = "0.80.7";'
  assert_contains "$package_text" 'hash = "sha256-new-src";'
  assert_contains "$package_text" 'npmDepsHash = "sha256-new-deps";'
  assert_contains "$lock_text" '"integrity": "sha512-core"'
  assert_contains "$lock_text" '"integrity": "sha512-ai"'
  assert_contains "$lock_text" '"integrity": "sha512-tui"'
  assert_equals '-rw-r--r--' "$(LC_ALL=C ls -l "$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json" | awk '{print $1}')"

  unset -f curl nix nix-instantiate tar
}

test_update_pi_release_package_dry_run_skips_network() {
  DRY=true
  curl() {
    echo "curl should not run in dry-run mode" >> "$ERROR_FILE"
    return 1
  }

  local output
  output=$(_update_pi_release_package 2>&1)

  assert_contains "$output" "Would update Pi package from the latest npm release"

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
  nix-instantiate() { return 0; }
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

  unset -f curl nix nix-instantiate tar
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
