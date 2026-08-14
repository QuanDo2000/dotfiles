#!/usr/bin/env bash
# Pinned Pi, Codex, and Obsidian Headless release update tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_update_all_dependency_pins_runs_every_managed_updater() {
  local calls="$TEST_TMPDIR/calls.log" name
  for name in \
    _update_lix_installer_pins \
    _update_codex_release_package \
    _update_pi_release_package \
    _update_obsidian_headless_package \
    _update_codebase_memory_release \
    _update_fff_release \
    _update_pi_extensions_release \
    _update_webcord_release \
    _update_anki_zoom \
    _update_firacode_pin \
    _update_vendored_skills \
    _update_neovim_plugins; do
    eval "$name() { printf '%s\\n' '$name' >> '$calls'; }"
  done

  _run_python_pin_batch() { printf '%s\n' _run_python_pin_batch >> "$calls"; }
  _update_all_dependency_pins

  assert_equals $'_update_lix_installer_pins\n_update_codex_release_package\n_update_pi_release_package\n_update_obsidian_headless_package\n_run_python_pin_batch' "$(<"$calls")"

  for name in \
    _update_lix_installer_pins _update_codex_release_package _update_pi_release_package \
    _update_obsidian_headless_package _update_codebase_memory_release _update_fff_release \
    _update_pi_extensions_release _update_webcord_release _update_anki_zoom \
    _update_firacode_pin _update_vendored_skills _update_neovim_plugins; do
    unset -f "$name"
  done
  unset -f _run_python_pin_batch
}

test_codebase_memory_verification_uses_cosign_without_nested_nix() {
  local source="$REPO_DIR/scripts/update_pins.py"
  local source_text
  source_text="$(<"$source")"
  assert_contains "$source_text" '"cosign", "verify-blob"'
  assert_contains "$source_text" '"--bundle", str(bundle)'
  assert_contains "$source_text" '"--certificate-identity", "https://github.com/DeusData/codebase-memory-mcp/.github/workflows/release.yml@refs/heads/main"'
  assert_contains "$source_text" '"--certificate-oidc-issuer", "https://token.actions.githubusercontent.com"'
  assert_not_contains "$source_text" '"nix", "develop", f"path:{repo}", "-c", "cosign"'
}

test_python_pin_batch_uses_one_nix_develop_and_preserves_order() {
  local calls="$TEST_TMPDIR/pin-batch.log"
  nix() {
    printf '%s\n' "$*" >> "$calls"
    return 0
  }
  DRY=false
  _run_python_pin_batch \
    codebase-memory "codebase-memory release" \
    fff "FFF release" \
    pi-extensions "Pi extension closure"

  assert_equals "1" "$(wc -l < "$calls")"
  assert_contains "$(<"$calls")" "codebase-memory fff pi-extensions"
  unset -f nix
}

test_all_dependency_pin_updaters_dry_run_without_network() {
  DRY=true
  curl() { return 99; }
  git() { return 99; }
  npm() { return 99; }

  local output status=0
  output="$(_update_all_dependency_pins 2>&1)" || status=$?

  assert_equals "0" "$status"
  for label in \
    "Lix installer" "Codex package" "Pi package" "Obsidian Headless" \
    "codebase-memory" "FFF" "Pi extension closure" "WebCord" "Anki Zoom" \
    "FiraCode Nerd Font" "vendored agent skills" "Neovim plugins"; do
    assert_contains "$output" "$label"
  done

  unset -f curl git npm
}

test_dependency_clean_check_detects_dirty_linked_worktree() {
  local repository="$TEST_TMPDIR/repository" worktree="$TEST_TMPDIR/worktree" old_dotfiles="$DOTFILES_DIR"
  git init -q "$repository"
  git -C "$repository" config user.email test@example.com
  git -C "$repository" config user.name Test
  printf 'clean\n' > "$repository/file"
  git -C "$repository" add file
  git -C "$repository" commit -qm initial
  git -C "$repository" worktree add -q "$worktree"
  printf 'dirty\n' >> "$worktree/file"
  DOTFILES_DIR="$worktree"

  local output status=0
  output="$(_require_clean_dependency_tree 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_contains "$output" "requires a clean repository"
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_fingerprint_binds_head() {
  local repo="$TEST_TMPDIR/head-fingerprint" old_dotfiles="$DOTFILES_DIR" before after
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'content\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  DOTFILES_DIR="$repo"
  before="$(_dependency_update_fingerprint)"
  git -C "$repo" commit --allow-empty -qm next
  after="$(_dependency_update_fingerprint)"
  [[ "$before" != "$after" ]] || echo "  fingerprint must include HEAD" >> "$ERROR_FILE"
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_marker_rejects_unvalidated_state() {
  local repo="$TEST_TMPDIR/marker-state" old_dotfiles="$DOTFILES_DIR" expected status=0
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'clean\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  printf 'validated\n' > "$repo/managed"
  DOTFILES_DIR="$repo"
  expected="$(_dependency_update_fingerprint)"
  printf 'tampered\n' > "$repo/managed"

  _write_dependency_update_marker ai "$expected" || status=$?

  assert_equals "1" "$status"
  if [[ -e "$repo/.git/dotfile-ai-update" ]]; then
    echo "  marker must not record unvalidated state" >> "$ERROR_FILE"
  fi
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_marker_requires_validated_fingerprint() {
  local repo="$TEST_TMPDIR/marker-expected" old_dotfiles="$DOTFILES_DIR" status=0
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'clean\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  printf 'changed\n' > "$repo/managed"
  DOTFILES_DIR="$repo"

  _write_dependency_update_marker ai || status=$?

  assert_equals "1" "$status"
  if [[ -e "$repo/.git/dotfile-ai-update" ]]; then
    echo "  marker must require validated fingerprint" >> "$ERROR_FILE"
  fi
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_fingerprint_fails_when_git_inspection_fails() {
  local old_dotfiles="$DOTFILES_DIR" status=0
  DOTFILES_DIR="$TEST_TMPDIR/fingerprint-failure"
  mkdir -p "$DOTFILES_DIR"
  git() {
    case "$*" in
      *'rev-parse HEAD'*) printf '0123456789012345678901234567890123456789\n' ;;
      *'ls-files --others'*) : ;;
      *'diff --binary HEAD'*) return 1 ;;
      *) return 1 ;;
    esac
  }

  _dependency_update_fingerprint >/dev/null || status=$?

  assert_equals "1" "$status"
  unset -f git
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_pending_reports_git_inspection_failure() {
  local repo="$TEST_TMPDIR/pending-git-failure" old_dotfiles="$DOTFILES_DIR" output status=0
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'clean\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  printf 'changed\n' > "$repo/managed"
  DOTFILES_DIR="$repo"
  printf 'fingerprint\n' > "$repo/.git/dotfile-ai-update"
  git() {
    if [[ "$*" == *'status --porcelain'* ]]; then return 1; fi
    command git "$@"
  }

  output="$(_dependency_update_pending ai 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_contains "$output" "Failed to inspect dependency repository"
  unset -f git
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_update_lock_is_shared_by_linked_worktrees() {
  if ! declare -F _acquire_dependency_update_lock >/dev/null; then
    echo "  missing dependency update lock" >> "$ERROR_FILE"
    return
  fi
  local repo="$TEST_TMPDIR/common-lock" worktree="$TEST_TMPDIR/common-lock-worktree"
  local old_dotfiles="$DOTFILES_DIR" lock status=0
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  : > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  git -C "$repo" worktree add -q "$worktree"
  DOTFILES_DIR="$repo"
  _acquire_dependency_update_lock
  lock="$DEPENDENCY_UPDATE_LOCK"
  DOTFILES_DIR="$worktree"

  _acquire_dependency_update_lock >/dev/null || status=$?

  assert_equals "1" "$status"
  DOTFILES_DIR="$repo"
  _release_dependency_update_lock "$lock"
  DEPENDENCY_UPDATE_LOCK=
  git -C "$repo" worktree remove --force "$worktree"
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_update_lock_rejects_live_owner() {
  if ! declare -F _acquire_dependency_update_lock >/dev/null; then
    echo "  missing dependency update lock" >> "$ERROR_FILE"
    return
  fi
  local repo="$TEST_TMPDIR/dependency-lock" old_dotfiles="$DOTFILES_DIR" lock status=0
  git init -q "$repo"
  DOTFILES_DIR="$repo"
  _acquire_dependency_update_lock
  lock="$DEPENDENCY_UPDATE_LOCK"

  _acquire_dependency_update_lock >/dev/null || status=$?

  assert_equals "1" "$status"
  _release_dependency_update_lock "$lock"
  DEPENDENCY_UPDATE_LOCK=
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_marker_rejects_opposite_scope() {
  local repo="$TEST_TMPDIR/marker-conflict" old_dotfiles="$DOTFILES_DIR" status=0
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'clean\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  printf 'changed\n' > "$repo/managed"
  DOTFILES_DIR="$repo"
  local expected
  expected="$(_dependency_update_fingerprint)"
  _write_dependency_update_marker full "$expected"

  _write_dependency_update_marker ai "$expected" || status=$?

  assert_equals "1" "$status"
  if [[ -e "$repo/.git/dotfile-ai-update" ]]; then
    echo "  conflicting AI marker must not be written" >> "$ERROR_FILE"
  fi
  DOTFILES_DIR="$old_dotfiles"
}

test_non_git_dependency_refresh_fails_without_mutation() {
  local root="$TEST_TMPDIR/non-git-refresh" old_dotfiles="$DOTFILES_DIR" status=0
  mkdir -p "$root"
  printf 'old\n' > "$root/managed"
  DOTFILES_DIR="$root"
  _test_live_refresh() { printf 'changed\n' > "$DOTFILES_DIR/managed"; }
  _validate_dependency_update() { :; }

  _refresh_dependency_set _test_live_refresh || status=$?

  assert_equals "1" "$status"
  assert_equals "old" "$(<"$root/managed")"
  unset -f _test_live_refresh _validate_dependency_update
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_markers_are_scoped() {
  local repo="$TEST_TMPDIR/scoped-marker" old_dotfiles="$DOTFILES_DIR"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'clean\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  printf 'changed\n' > "$repo/managed"
  DOTFILES_DIR="$repo"
  local expected
  expected="$(_dependency_update_fingerprint)"

  _write_dependency_update_marker ai "$expected"

  assert_file_exists "$repo/.git/dotfile-ai-update"
  if [[ -e "$repo/.git/dotfile-dependency-update" ]]; then
    echo "  AI update must not write full dependency marker" >> "$ERROR_FILE"
  fi
  assert_exit_code 0 _dependency_update_pending ai
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_refresh_runs_selected_updater_in_isolated_worktree() {
  local repo="$TEST_TMPDIR/selected-refresh" old_dotfiles="$DOTFILES_DIR" source_dir="$TEST_TMPDIR/source-path"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'old\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  DOTFILES_DIR="$repo"
  source_dir="$repo"
  _test_ai_refresh() {
    [[ "$DOTFILES_DIR" != "$source_dir" ]] || return 1
    printf 'ai\n' > "$DOTFILES_DIR/managed"
  }
  _validate_dependency_update() { [[ "$(<"$DOTFILES_DIR/managed")" == ai ]]; }

  _refresh_dependency_set _test_ai_refresh

  assert_equals "ai" "$(<"$repo/managed")"
  unset -f _test_ai_refresh _validate_dependency_update
  DOTFILES_DIR="$old_dotfiles"
}

test_dependency_refresh_preserves_concurrent_changes() {
  local repo
  repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'old\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial

  if (
    SOURCE_REPO="$repo"
    DOTFILES_DIR="$repo"
    _update_flake_inputs() {
      printf 'updated\n' > "$DOTFILES_DIR/managed"
      printf 'concurrent\n' > "$SOURCE_REPO/concurrent"
    }
    _update_all_dependency_pins() { :; }
    _validate_dependency_update() { :; }
    _refresh_dependency_set
  ); then
    fail_soft "dependency refresh should reject concurrent changes"
  fi

  assert_equals "old" "$(<"$repo/managed")"
  assert_equals "concurrent" "$(<"$repo/concurrent")"
}

test_dependency_refresh_uses_isolated_worktree() {
  local repo status refresh_status=0
  repo="$TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'old\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial

  (
    DOTFILES_DIR="$repo"
    _update_flake_inputs() { printf 'new\n' > "$DOTFILES_DIR/managed"; }
    _update_all_dependency_pins() { printf 'added\n' > "$DOTFILES_DIR/added"; }
    _validate_dependency_update() { [[ "$(<"$DOTFILES_DIR/managed")" == "new" ]]; }
    _refresh_dependency_set
  ) || refresh_status=$?

  assert_equals "0" "$refresh_status"
  assert_equals "new" "$(<"$repo/managed")"
  assert_equals "added" "$(<"$repo/added")"
  status="$(git -C "$repo" status --short)"
  assert_contains "$status" ' M managed'
  assert_contains "$status" '?? added'
  assert_equals "1" "$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')"

  local releases
  releases="$(<"$REPO_DIR/scripts/releases.sh")"
  assert_not_contains "$releases" 'git -C "$DOTFILES_DIR" reset --hard HEAD'
  assert_not_contains "$releases" 'git -C "$DOTFILES_DIR" clean -fd'
}

test_dependency_approval_shows_full_diff_before_activation() {
  local releases
  releases="$(<"$REPO_DIR/scripts/releases.sh")"

  assert_contains "$releases" 'git -C "$DOTFILES_DIR" diff --'
  assert_contains "$releases" 'git -C "$DOTFILES_DIR" diff --cached --'
  assert_contains "$releases" 'git -C "$DOTFILES_DIR" ls-files --others --exclude-standard'
}

test_npm_prefetch_uses_repo_locked_nixpkgs() {
  local releases flake
  releases="$(<"$REPO_DIR/scripts/releases.sh")"
  flake="$(<"$REPO_DIR/flake.nix")"

  assert_contains "$releases" 'path:$DOTFILES_DIR#prefetch-npm-deps'
  assert_not_contains "$releases" 'nixpkgs#prefetch-npm-deps'
  assert_contains "$flake" 'packages.x86_64-linux.prefetch-npm-deps = linuxPkgs.prefetch-npm-deps;'
  assert_contains "$flake" 'packages.aarch64-darwin.prefetch-npm-deps = darwinPkgs.prefetch-npm-deps;'
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

test_release_owner_identity_rejects_pid_reuse() {
  local pid="${BASHPID:-$$}" start status=0
  start="$(_release_process_start "$pid")"

  _release_owner_is_live "$pid|wrong start" || status=$?
  assert_equals "1" "$status"
  status=0
  _release_owner_is_live "$pid|$start" || status=$?
  assert_equals "0" "$status"
}

test_release_transaction_fails_closed_on_incomplete_lock_owner() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  printf 'package\n' > "$package_file"
  printf 'lock\n' > "$lock_file"
  mkdir -p "$transaction_dir"
  printf 'initializing\n' > "$transaction_dir/partial"

  local output exit_code=0
  output=$(_acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "update lock owner is incomplete"
  if [[ ! -d "$transaction_dir" ]]; then
    echo "  FAILED: incomplete update lock should remain for manual inspection" >> "$ERROR_FILE"
  fi
}

test_release_transaction_rejects_linked_owner_directory() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  local outside="$TEST_TMPDIR/outside"
  local linked_owner="$transaction_dir.owner.evil"
  printf 'current package\n' > "$package_file"
  printf 'current lock\n' > "$lock_file"
  mkdir "$outside"
  printf '99999999|dead\n' > "$outside/pid"
  printf 'prepared\n' > "$outside/state"
  printf 'attacker package\n' > "$outside/package.backup"
  printf 'attacker lock\n' > "$outside/lock.backup"
  ln -s "$outside" "$linked_owner"
  ln -s "$(basename "$linked_owner")" "$transaction_dir"

  local output exit_code=0
  output=$(_acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "owner directory is invalid"
  assert_equals "current package" "$(<"$package_file")"
  assert_equals "current lock" "$(<"$lock_file")"
}

test_release_transaction_cleans_unpublished_owner_when_lock_publish_fails() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  printf 'package\n' > "$package_file"
  printf 'lock\n' > "$lock_file"
  ln() { return 1; }

  local output exit_code=0
  output=$(_acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to publish test release update lock"
  if [[ -e "$transaction_dir" ]] || [[ -n "$(printf '%s\n' "$transaction_dir".owner.* | grep -v '\*' || true)" ]]; then
    echo "  FAILED: unpublished transaction owner should be cleaned" >> "$ERROR_FILE"
  fi
  unset -f ln
}

test_release_transaction_rejects_live_owner() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  printf 'old package\n' > "$package_file"
  printf 'old lock\n' > "$lock_file"
  _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release"

  local output exit_code=0
  output=$(_acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "test release update already running"
  _release_release_transaction "$transaction_dir"
}

test_release_transaction_recovers_orphaned_recovery_journal() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  local claim="$transaction_dir.claim.old"
  local journal="$claim.journal"
  local owner_dir="$transaction_dir.owner.old"
  printf 'new package\n' > "$package_file"
  printf 'new lock\n' > "$lock_file"
  printf '99999999|dead\n' > "$claim"
  mkdir "$owner_dir"
  ln -s "$(basename "$owner_dir")" "$journal"
  printf 'prepared\n' > "$journal/state"
  printf 'old package\n' > "$journal/package.backup"
  printf 'old lock\n' > "$journal/lock.backup"

  _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release"

  assert_equals "old package" "$(<"$package_file")"
  assert_equals "old lock" "$(<"$lock_file")"
  if [[ -e "$claim" || -e "$journal" || -e "$owner_dir" ]]; then
    echo "  FAILED: orphaned recovery journal should be cleared" >> "$ERROR_FILE"
  fi
  _release_release_transaction "$transaction_dir"
}

test_release_transaction_recovers_interrupted_pair() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  printf 'new package\n' > "$package_file"
  printf 'new lock\n' > "$lock_file"
  mkdir "$transaction_dir"
  printf '99999999|dead\n' > "$transaction_dir/pid"
  printf 'prepared\n' > "$transaction_dir/state"
  printf 'old package\n' > "$transaction_dir/package.backup"
  printf 'old lock\n' > "$transaction_dir/lock.backup"
  mkdir "$transaction_dir/stage"
  printf 'partial download\n' > "$transaction_dir/stage/archive.tgz"
  sync() {
    local count=0
    [[ ! -f "$TEST_TMPDIR/sync-count" ]] || count="$(<"$TEST_TMPDIR/sync-count")"
    printf '%s\n' "$((count + 1))" > "$TEST_TMPDIR/sync-count"
    printf '%s|%s\n' "$(<"$package_file")" "$(<"$lock_file")" > "$TEST_TMPDIR/synced-release"
  }

  _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release"

  assert_equals "old package" "$(<"$package_file")"
  assert_equals "old lock" "$(<"$lock_file")"
  assert_equals "old package|old lock" "$(<"$TEST_TMPDIR/synced-release")"
  if [[ "$(<"$TEST_TMPDIR/sync-count")" -lt 3 ]]; then
    echo "  FAILED: recovery should sync restored files, state deletion, and cleanup" >> "$ERROR_FILE"
  fi
  if [[ -e "$transaction_dir/state" || -e "$transaction_dir/package.backup" || -e "$transaction_dir/lock.backup" || -e "$transaction_dir/stage" ]]; then
    echo "  FAILED: recovered transaction journal and staging should be cleared" >> "$ERROR_FILE"
  fi
  _release_release_transaction "$transaction_dir"
  unset -f sync
}

test_release_file_pair_rolls_back_when_second_replace_fails() {
  local package_file="$TEST_TMPDIR/package.nix"
  local lock_file="$TEST_TMPDIR/package-lock.json"
  local staged_package="$TEST_TMPDIR/package.nix.staged"
  local staged_lock="$TEST_TMPDIR/package-lock.json.staged"
  printf 'old package\n' > "$package_file"
  printf 'old lock\n' > "$lock_file"
  local transaction_dir="$TEST_TMPDIR/release.transaction"
  printf 'new package\n' > "$staged_package"
  printf 'new lock\n' > "$staged_lock"
  _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "test release"
  mv() {
    if [[ "${2:-}" == "$lock_file" && ! -e "$TEST_TMPDIR/lock-move-failed" ]]; then
      : > "$TEST_TMPDIR/lock-move-failed"
      return 1
    fi
    command mv "$@"
  }

  local output exit_code=0
  output=$(_install_release_file_pair "$staged_package" "$package_file" "$staged_lock" "$lock_file" "test release" "$transaction_dir" 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Failed to install test release files"
  assert_equals "old package" "$(<"$package_file")"
  assert_equals "old lock" "$(<"$lock_file")"
  if [[ -e "$staged_package" || -e "$staged_lock" ]]; then
    echo "  FAILED: staged release files should be cleaned after rollback" >> "$ERROR_FILE"
  fi
  _release_release_transaction "$transaction_dir"

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

test_obsidian_headless_generates_lock_when_archive_omits_it() {
  local lock="$TEST_TMPDIR/generated-lock.json"
  curl() {
    local output
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "-o" ]] && { output="$2"; shift 2; continue; }
      shift
    done
    : > "$output"
  }
  tar() {
    if [[ "$*" == *package/package-lock.json* ]]; then
      return 1
    fi
    printf '%s\n' '{"name":"obsidian-headless","version":"1.2.3","dependencies":{"example":"1.0.0"}}'
  }
  nix() {
    printf '%s\n' '{"lockfileVersion":3,"packages":{}}' > package-lock.json
  }

  _download_obsidian_headless_package_lock 1.2.3 "$lock"

  assert_equals "3" "$(jq -r .lockfileVersion "$lock")"
  unset -f curl tar nix
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
