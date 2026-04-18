# Odin Language Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Odin as the second language under the existing `dotfile languages [LANG]` umbrella. Latest release is fetched from the official GitHub releases API, downloaded over HTTPS, and integrity-checked against the SHA-256 `digest` field in the same response.

**Architecture:** Append per-language functions to `scripts/languages.sh` (mirroring the Zig pattern), extend `install_languages` and `update_languages`. No `dotfile`-script changes — the CLI dispatch is already wired. Install layout: `~/.local/odin-<tag>/` with `~/.local/bin/odin` symlinked to it. Linux + macOS only.

**Tech Stack:** Bash 4+ on Linux, bash 3.2-compatible patterns where macOS's stock bash matters (no `mapfile -t`). Reuses `_sha256`, `_shuffle_lines`, `ensure_jq`, `http_get_retry`, `resolve_symlink`, `fail`, `info`, `success` from earlier work. No new external dependencies — Odin's GitHub API response carries the SHA-256 in its `digest` field.

**Spec:** `docs/superpowers/specs/2026-04-18-odin-language-install-design.md`.

**Pre-execution baseline:** 163 tests passing on `main`. After this plan: ~180 passing (16 new tests across the tasks below).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Modify | Append `odin_target_triple`, `odin_latest_release`, `odin_current_installed_version`, `install_odin`, `update_odin`. Extend `install_languages` and `update_languages`. |
| `tests/bash/test_languages.sh` | Modify | Per-function tests for the new code, extend the umbrella tests. |
| `CLAUDE.md` | Modify | Add a single `dotfile languages [LANG]` entry to the `Key Commands` block. |

No changes to `dotfile`, `dotfile.ps1`, `tests/bash/runner.sh`, `tests/bash/helpers.sh`, or `tests/bash/test_cli.sh`.

---

## Reused test stubbing pattern

Same idiom as the Zig tests — shadow a real function inside the test body and `export -f` so the override propagates into subshells:

```bash
test_xyz() {
  http_get_retry() { cat <<'JSON'
{"tag_name": "dev-2026-04", "assets": [...]}
JSON
  }
  export -f http_get_retry
  ...
}
```

Cleanup happens automatically because each test runs in its own subshell.

---

## Task 1: `odin_target_triple`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh` (after the last existing test, before EOF):

```bash
# ---------------------------------------------------------------------------
# odin_target_triple
# ---------------------------------------------------------------------------

test_odin_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(odin_target_triple)"
  assert_equals "linux-amd64" "$result"
}

test_odin_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(odin_target_triple)"
  assert_equals "linux-arm64" "$result"
}

test_odin_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(odin_target_triple)"
  assert_equals "macos-amd64" "$result"
}

test_odin_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(odin_target_triple)"
  assert_equals "macos-arm64" "$result"
}

test_odin_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( odin_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: odin_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 5 new tests FAIL with "odin_target_triple: command not found".

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh` (after the existing functions — placement near the other `*_target_triple`-shaped helpers is fine; the file's convention is callee-defined-before-caller, and Odin's callers haven't been added yet, so anywhere after `_shuffle_lines` works):

```bash
# Map (uname -s, uname -m) to Odin's release-asset slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
odin_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "linux-amd64" ;;
    Linux/aarch64)       echo "linux-arm64" ;;
    Linux/arm64)         echo "linux-arm64" ;;
    Darwin/x86_64)       echo "macos-amd64" ;;
    Darwin/arm64)        echo "macos-arm64" ;;
    Darwin/aarch64)      echo "macos-arm64" ;;
    *) fail "Unsupported platform for odin install: $os/$arch" ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: existing tests + 5 new ones, all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add odin_target_triple"
```

---

## Task 2: `odin_latest_release`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# odin_latest_release
# ---------------------------------------------------------------------------

test_odin_latest_release_uses_passed_json() {
  # If a JSON arg is given, return it verbatim — http_get_retry must NOT be called.
  http_get_retry() {
    echo "  FAILED: http_get_retry should not be called when JSON arg supplied" >> "$ERROR_FILE"
    return 1
  }
  export -f http_get_retry

  local result
  result="$(odin_latest_release '{"tag_name": "dev-2026-04"}')"
  assert_equals '{"tag_name": "dev-2026-04"}' "$result"
}

test_odin_latest_release_fetches_when_no_arg() {
  http_get_retry() { echo '{"tag_name": "dev-2026-04"}'; }
  export -f http_get_retry

  local result
  result="$(odin_latest_release)"
  assert_equals '{"tag_name": "dev-2026-04"}' "$result"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 2 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Print the JSON body of the latest Odin release from the GitHub API.
# Optionally accepts a JSON string as $1 to skip the network fetch — lets
# install_odin fetch once and reuse the body for tag/digest/url lookups.
odin_latest_release() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://api.github.com/repos/odin-lang/Odin/releases/latest")" \
      || fail "Failed to fetch Odin releases/latest"
  fi
  echo "$json"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 2 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add odin_latest_release"
```

---

## Task 3: `odin_current_installed_version`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# odin_current_installed_version
# ---------------------------------------------------------------------------

test_odin_current_installed_version_none() {
  local result
  result="$(odin_current_installed_version)"
  assert_equals "" "$result"
}

test_odin_current_installed_version_ours_returns_tag() {
  mkdir -p "$HOME/.local/odin-dev-2026-04"
  touch "$HOME/.local/odin-dev-2026-04/odin"
  ln -s "$HOME/.local/odin-dev-2026-04/odin" "$HOME/.local/bin/odin"

  local result
  result="$(odin_current_installed_version)"
  assert_equals "dev-2026-04" "$result"
}

test_odin_current_installed_version_foreign_returns_empty() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/odin"
  ln -s "$HOME/elsewhere/odin" "$HOME/.local/bin/odin"

  local result
  result="$(odin_current_installed_version)"
  assert_equals "" "$result"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 3 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Print the currently-installed Odin tag IF it was installed by this script.
# Returns empty string for: no install, foreign install (e.g., system odin).
# Detection rule: ~/.local/bin/odin must be a symlink whose target is
# ~/.local/odin-<tag>/odin.
odin_current_installed_version() {
  local link="$HOME/.local/bin/odin"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  local prefix="$HOME/.local/odin-"
  local suffix="/odin"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#$prefix}"
      middle="${middle%$suffix}"
      case "$middle" in
        */*) return 0 ;;
      esac
      echo "$middle"
      ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 3 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add odin_current_installed_version"
```

---

## Task 4: `install_odin`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

The download / SHA-256 / extract logic is implemented but only the dry-run + already-installed paths are unit-tested (same trade-off as `install_zig`; manual smoke covers the network paths).

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# install_odin
# ---------------------------------------------------------------------------

test_install_odin_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Finished"
  if [[ -e "$HOME/.local/odin-dev-2026-04" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_odin_already_installed_short_circuits() {
  # Pretend latest is dev-2026-04 AND that it's already installed.
  mkdir -p "$HOME/.local/odin-dev-2026-04"
  touch "$HOME/.local/odin-dev-2026-04/odin"
  ln -s "$HOME/.local/odin-dev-2026-04/odin" "$HOME/.local/bin/odin"

  http_get_retry() { echo '{"tag_name": "dev-2026-04", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
  assert_contains "$output" "Already installed Odin dev-2026-04"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 2 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Install (or upgrade) Odin from the official GitHub releases.
#
# Layout: extracts to ~/.local/odin-<tag>/ and symlinks ~/.local/bin/odin.
# Skips if the target tag is already installed.
install_odin() {
  info "Installing Odin..."
  ensure_jq

  local triple
  triple="$(odin_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Odin for $triple"
    success "Finished installing Odin (dry run)"
    return 0
  fi

  local release_json
  release_json="$(odin_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Odin releases/latest"
  fi
  local asset="odin-${triple}-${tag}.tar.gz"

  local current
  current="$(odin_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Odin $tag"
    return 0
  fi

  local digest
  digest="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // empty')"
  if [[ -z "$digest" ]]; then
    fail "Could not find digest for $asset in Odin releases/latest"
  fi
  # GitHub formats digests as "sha256:<hex>"; strip the prefix.
  local expected_sha="${digest#sha256:}"
  if [[ "$expected_sha" == "$digest" ]]; then
    fail "Unexpected digest format for $asset: $digest"
  fi

  local asset_url
  asset_url="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .browser_download_url // empty')"
  if [[ -z "$asset_url" ]]; then
    fail "Could not find download URL for $asset in Odin releases/latest"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tar_path="$tmpdir/$asset"
  info "Downloading $asset_url"
  curl -sfL "$asset_url" -o "$tar_path" \
    || fail "Failed to download $asset_url"

  local got_sha
  got_sha="$(_sha256 "$tar_path")"
  if [[ "$got_sha" != "$expected_sha" ]]; then
    fail "sha256 mismatch for $asset (expected $expected_sha, got $got_sha)"
  fi

  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tar_path" -C "$extract_dir" \
    || fail "Failed to extract Odin tarball"
  # Portable single-dir check (avoid mapfile/-readarray for bash 3.2 on macOS).
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "Odin tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi

  local target_dir="$HOME/.local/odin-$tag"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Odin into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/odin" "$HOME/.local/bin/odin" \
    || fail "Failed to create ~/.local/bin/odin symlink"

  # Clean up old versions (any ~/.local/odin-*/ that isn't the current one).
  local old
  for old in "$HOME"/.local/odin-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Odin $tag"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 2 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add install_odin with SHA-256 verification"
```

---

## Task 5: `update_odin`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# update_odin
# ---------------------------------------------------------------------------

test_update_odin_no_op_when_not_installed() {
  local output
  output=$(update_odin 2>&1)
  assert_equals "" "$output"
}

test_update_odin_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/odin"
  ln -s "$HOME/elsewhere/odin" "$HOME/.local/bin/odin"

  local output
  output=$(update_odin 2>&1)
  assert_equals "" "$output"
}

test_update_odin_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/odin-dev-2026-03"
  touch "$HOME/.local/odin-dev-2026-03/odin"
  ln -s "$HOME/.local/odin-dev-2026-03/odin" "$HOME/.local/bin/odin"

  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(update_odin 2>&1)
  assert_contains "$output" "Installing Odin"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 3 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Update Odin — but only if it was installed by this script. Foreign installs
# (system, brew) are left alone.
update_odin() {
  local current
  current="$(odin_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_odin
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 3 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add update_odin"
```

---

## Task 6: Extend `install_languages` umbrella

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests + replace existing all-arg test**

In `tests/bash/test_languages.sh`, find the existing `test_install_languages_all_arg` and REPLACE it with a stricter version that checks BOTH languages run. Then APPEND a new test for the `odin` arg:

```bash
test_install_languages_all_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages all 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
}

test_install_languages_odin_only_arg() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages odin 2>&1)
  assert_contains "$output" "Installing Odin"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages odin should not run Zig" >> "$ERROR_FILE"
  fi
}
```

Also update the existing `test_install_languages_dry_run` to assert both languages run (it covers the no-arg case, which also defaults to "all"):

```bash
test_install_languages_dry_run() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: at least the new `test_install_languages_odin_only_arg` FAILs (no `odin)` arm yet); the updated `_all_arg` and `_dry_run` tests also FAIL because the umbrella doesn't yet call `install_odin`.

- [ ] **Step 3: Implement**

Edit `install_languages` in `scripts/languages.sh`. Replace:

```bash
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig ;;
    zig)    install_zig ;;
    *)      fail "Unknown language: $target" ;;
  esac
}
```

with:

```bash
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig; install_odin ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    *)      fail "Unknown language: $target" ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: all updated and new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add Odin to install_languages umbrella"
```

---

## Task 7: Update `update_languages` umbrella

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Update the existing dry-run test (no new test needed)**

The existing `test_update_languages_dry_run_no_install` already asserts zero output when nothing is installed. Adding `update_odin` to the umbrella keeps this true (both `update_zig` and `update_odin` no-op silently). No test change needed for this task — but verify the test still passes after step 3.

- [ ] **Step 2: Run baseline**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: existing tests pass (we haven't changed code yet).

- [ ] **Step 3: Implement**

Edit `update_languages` in `scripts/languages.sh`. Replace:

```bash
update_languages() {
  update_zig
}
```

with:

```bash
update_languages() {
  update_zig
  update_odin
}
```

- [ ] **Step 4: Run, confirm still passes**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: `test_update_languages_dry_run_no_install` still PASSES (no Odin install present → silent).

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh
git commit -m "Add Odin to update_languages umbrella"
```

---

## Task 8: Update `CLAUDE.md` Key Commands

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read the current Key Commands block**

```bash
sed -n '/^## Key Commands/,/^## /p' CLAUDE.md | head -25
```
Expected: a fenced bash block listing `dotfile`, `dotfile symlinks`, `dotfile packages`, `dotfile extras`, `dotfile verify`, `dotfile -d`, `dotfile -f`. The `languages` command is missing.

- [ ] **Step 2: Add the languages line**

Edit `CLAUDE.md`. In the `## Key Commands` block, between the existing `dotfile verify` line and the `dotfile -d <command>` line, add:

```
dotfile languages [LANG]     # Install language toolchains (zig, odin)
```

The result should look like:

```bash
dotfile                      # Full setup (packages → extras → symlinks)
dotfile symlinks             # Create symlinks only
dotfile packages             # Install system packages only
dotfile extras               # Install oh-my-zsh, zsh plugins, tmux plugins
dotfile verify               # Verify installation
dotfile languages [LANG]     # Install language toolchains (zig, odin)
dotfile -d <command>         # Dry run
dotfile -f <command>         # Force overwrite existing files
```

- [ ] **Step 3: Verify the change**

```bash
grep -A 1 'languages \[LANG\]' CLAUDE.md
```
Expected: the new line shows up exactly once.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Document languages subcommand in CLAUDE.md Key Commands"
```

---

## Task 9: Full test sweep

**Files:** none (verification only)

- [ ] **Step 1: Run the bash suite on host**

```bash
bash tests/bash/runner.sh --no-docker
```
Expected: ~180 passed / 0 failed (163 baseline + 16 new — exact count depends on which existing tests get replaced vs added; the important assertion is **0 failed**).

- [ ] **Step 2: Run the bash suite in Docker**

```bash
bash tests/bash/runner.sh
```
Expected: same count, **0 failed**. First run rebuilds the image (slow); subsequent runs reuse the cache.

- [ ] **Step 3: If anything fails, fix the underlying cause**

Most likely failure modes:
- A test that stubs `http_get_retry` to return a JSON missing the `assets` array — `install_odin` step that does `jq '.assets[] | select(...)'` would emit no output and the empty-check fires. Fix the stub fixture, not the implementation.
- A test interfering with another via leaked state. Inspect the `setup`/`teardown` calls.

Do NOT loosen test assertions to make them pass.

- [ ] **Step 4: No commit**

This task ends when both runs are green.

---

## Task 10: Manual smoke test (Arch host)

**Files:** none (manual verification only)

The download / SHA-256 / extract / atomic swap / cleanup paths can't be unit-tested. Run these manually before considering the feature done.

- [ ] **Step 1: Fresh install**

```bash
rm -rf "$HOME"/.local/odin-* "$HOME/.local/bin/odin"
bash ./dotfile languages odin
"$HOME/.local/bin/odin" version
```

Expected: prints the same tag as `https://github.com/odin-lang/Odin/releases/latest`.

- [ ] **Step 2: Re-install is idempotent**

```bash
bash ./dotfile languages odin
```

Expected: log line `Already installed Odin <tag>`. Returns instantly. No new files in `~/.local/odin-*`.

- [ ] **Step 3: Update no-ops on the latest version**

```bash
bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_odin'
```

Expected: `Installing Odin...` then `Already installed Odin <tag>`. (Direct call so we don't trigger `update_packages`'s sudo prompt.)

- [ ] **Step 4: Update ignores foreign installs**

```bash
mv "$HOME/.local/bin/odin" "$HOME/.local/bin/odin.ours"
touch "$HOME/.local/odin-foreign-test"
ln -s "$HOME/.local/odin-foreign-test" "$HOME/.local/bin/odin"
bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_odin' 2>&1 | grep -i odin || echo "(no odin output — as expected)"
rm -f "$HOME/.local/bin/odin" "$HOME/.local/odin-foreign-test"
mv "$HOME/.local/bin/odin.ours" "$HOME/.local/bin/odin"
```

Expected: zero matching output between the run and the grep — the cleanup line confirms the foreign install was correctly ignored.

- [ ] **Step 5: Umbrella runs both languages**

```bash
bash ./dotfile languages
```

Expected: `Installing Zig...` + `Already installed Zig <ztag>` + `Installing Odin...` + `Already installed Odin <otag>`. Both short-circuit.

- [ ] **Step 6: SHA-256 mismatch path (optional)**

Only needed if you want to manually verify the failure path. Briefly modify the shasum line in the script (e.g. set `expected_sha="badbad"`), re-run, observe the `fail "sha256 mismatch ..."`, then revert.

- [ ] **Step 7: macOS smoke test deferred**

No Mac available in this environment. Document this gap; defer macOS smoke until a Mac is on hand.

- [ ] **Step 8: No commit, no PR yet**

Once steps 1–5 pass, the feature is done and ready for the user to merge or PR.

---

## Self-review notes

- **Spec coverage:** All sections of the spec map to tasks. The function inventory's 5 functions → Tasks 1, 2, 3, 4, 5. The umbrella changes → Tasks 6, 7. CLAUDE.md → Task 8. Tests → woven into each function task. Manual smoke → Task 10.
- **Placeholder scan:** No "TBD" / "TODO" / "implement later" / "appropriate error handling". Every step has either runnable code, an exact command, or a concrete edit instruction.
- **Type / name consistency:** `odin_target_triple`, `odin_latest_release`, `odin_current_installed_version`, `install_odin`, `update_odin` consistent across tasks. Symlink layout `~/.local/odin-<tag>/odin` ↔ `~/.local/bin/odin` consistent. Asset name format `odin-${triple}-${tag}.tar.gz` consistent. `expected_sha` / `got_sha` naming consistent.
- **One thing worth flagging during execution:** Task 6 modifies an existing test (`test_install_languages_all_arg` and `test_install_languages_dry_run`) to assert both languages run. If a future language is added, those tests need re-tightening too. A comment in the test code would help — but YAGNI for now.
