# Zig Language Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `dotfile languages [LANG]` subcommand that installs Zig from the official community mirrors with full minisign signature verification, plus an `update_languages` step in the existing `update` flow.

**Architecture:** New `scripts/languages.sh` module sourced by `dotfile`. Per-language functions (currently just zig) plus an umbrella dispatcher. Install layout: `~/.local/zig-<version>/` with a stable symlink at `~/.local/bin/zig`. Updates only act on installs created by this script (detected by symlink target). Linux + macOS only.

**Tech Stack:** Bash 4+, `curl` (already used), `minisign` (auto-installed), `jq` (auto-installed; needed for parsing `index.json`), the existing test runner under `tests/bash/`.

**Spec:** See `docs/superpowers/specs/2026-04-17-zig-language-install-design.md`.

**Deviation from spec:** Spec didn't call out a JSON parser. Robust semver-aware extraction from `index.json` is much cleaner with `jq` than with grep, so this plan adds an `ensure_jq` helper that mirrors `ensure_minisign`. Both run at the top of `install_zig`. No other behaviour changes.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Create | `ZIG_PUBKEY` constant + 9 functions (`zig_target_triple`, `zig_latest_stable`, `zig_current_installed_version`, `ensure_minisign`, `ensure_jq`, `install_zig`, `update_zig`, `install_languages`, `update_languages`) |
| `dotfile` | Modify | Source new script; dispatch `languages [LANG]`; call `update_languages` from `update`; mention in `usage` |
| `tests/bash/helpers.sh` | Modify | Add `mock_uname_m`; reset `__MOCK_UNAME_M` in `cleanup_test_env` |
| `tests/bash/test_languages.sh` | Create | Unit tests for every new function |
| `tests/bash/test_cli.sh` | Modify | CLI dispatch tests for `languages` and `languages zig` |

---

## Test stubbing pattern

Several tests need to shadow real network/filesystem calls. The pattern (already used in this repo via `mock_uname`): redefine the function inside the test body. Bash uses last-definition-wins, and because tests run in subshells the override is automatically scoped to that test.

Example used throughout:

```bash
test_zig_latest_stable_picks_highest() {
  http_get_retry() { cat <<'JSON'
{"master": {}, "0.13.0": {}, "0.14.1": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.14.1" "$result"
}
```

---

## Task 0: Fetch the Zig signing pubkey

**Files:**
- Create: (none — info-gathering only)

This task records the public key value that Task 2 will hardcode into `scripts/languages.sh`. The key changes very rarely but does change; recording the date helps future maintenance.

- [ ] **Step 1: Visit https://ziglang.org/download/ in a browser**

Look for the "Tarball signatures are signed with the following minisign key" section. Copy the line beginning with `RWS...` (a one-line minisign public key, ~52 chars).

- [ ] **Step 2: Record the value and today's date**

Write down (you'll paste it into the script in Task 2):

```
ZIG_PUBKEY="<paste here>"
# Source: https://ziglang.org/download/  Copied: 2026-04-17
```

No commit for this task.

---

## Task 1: Add `mock_uname_m` test helper

**Files:**
- Modify: `tests/bash/helpers.sh`

- [ ] **Step 1: Write a failing test for the helper**

Append to `tests/bash/test_utils.sh` (existing file — pick this one because it already tests helper-adjacent things; if you'd rather create a separate `test_helpers.sh`, that's fine too):

```bash
test_mock_uname_m_overrides_uname_m() {
  init_test_env
  mock_uname_m aarch64
  local result
  result="$(uname -m)"
  assert_equals "aarch64" "$result"
  cleanup_test_env
}

test_cleanup_resets_uname_m() {
  init_test_env
  mock_uname_m aarch64
  cleanup_test_env
  init_test_env
  local result
  result="$(uname -m)"
  # After cleanup + fresh init, uname -m should be the real value (NOT "aarch64")
  if [[ "$result" == "aarch64" ]] && [[ "$(command uname -m)" != "aarch64" ]]; then
    echo "  FAILED: uname -m mock leaked across tests" >> "$ERROR_FILE"
  fi
  cleanup_test_env
}
```

- [ ] **Step 2: Run the new tests, confirm they fail**

Run:
```bash
bash tests/bash/runner.sh --no-docker test_utils.sh
```
Expected: both new tests FAIL (`mock_uname_m: command not found`).

- [ ] **Step 3: Add `mock_uname_m` and update `cleanup_test_env`**

Edit `tests/bash/helpers.sh`. The trick: both `mock_uname` and `mock_uname_m` need to install the **same** `uname()` body so calling them in any order leaves a function that handles both `uname` (no args) and `uname -m` correctly. The body reads from env vars and falls back to the real uname for whichever one isn't mocked.

Replace the existing `mock_uname` body with:

```bash
# Internal: install a uname() that respects __MOCK_UNAME and __MOCK_UNAME_M.
# Falls through to the real uname for whichever env var is unset.
_install_uname_mock() {
  uname() {
    if [[ "${1:-}" == "-m" ]]; then
      echo "${__MOCK_UNAME_M:-$(command uname -m)}"
    else
      echo "${__MOCK_UNAME:-$(command uname)}"
    fi
  }
  export -f uname
}

# Override uname (no args) to return the given OS string.
# Usage: mock_uname Darwin
mock_uname() {
  export __MOCK_UNAME="$1"
  _install_uname_mock
}

# Override uname -m to return the given architecture string.
# Usage: mock_uname_m aarch64
mock_uname_m() {
  export __MOCK_UNAME_M="$1"
  _install_uname_mock
}
```

And update `cleanup_test_env` to also clear `__MOCK_UNAME_M`:

```bash
cleanup_test_env() {
  export HOME="$ORIG_HOME"
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME 2>/dev/null || true
  unset __MOCK_UNAME_M 2>/dev/null || true
  rm -rf "$TEST_TMPDIR"
}
```

- [ ] **Step 4: Run the helper tests, confirm they pass**

Run:
```bash
bash tests/bash/runner.sh --no-docker test_utils.sh
```
Expected: both new tests PASS. No regressions in other `test_utils.sh` tests.

- [ ] **Step 5: Run the full bash suite to confirm `mock_uname` rework didn't break anything**

Run:
```bash
bash tests/bash/runner.sh --no-docker
```
Expected: all tests PASS (the `mock_uname` rewrite preserves prior behaviour because `uname` with no args still echoes `$__MOCK_UNAME`).

- [ ] **Step 6: Commit**

```bash
git add tests/bash/helpers.sh tests/bash/test_utils.sh
git commit -m "Add mock_uname_m test helper"
```

---

## Task 2: Create `scripts/languages.sh` skeleton + `zig_target_triple`

**Files:**
- Create: `scripts/languages.sh`
- Create: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests for `zig_target_triple`**

Create `tests/bash/test_languages.sh`:

```bash
#!/bin/bash
# Tests for scripts/languages.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh packages.sh languages.sh
}

teardown() {
  cleanup_test_env
}

# ---------------------------------------------------------------------------
# zig_target_triple
# ---------------------------------------------------------------------------

test_zig_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(zig_target_triple)"
  assert_equals "x86_64-linux" "$result"
}

test_zig_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(zig_target_triple)"
  assert_equals "aarch64-linux" "$result"
}

test_zig_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(zig_target_triple)"
  assert_equals "x86_64-macos" "$result"
}

test_zig_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(zig_target_triple)"
  assert_equals "aarch64-macos" "$result"
}

test_zig_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( zig_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: zig_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 5 FAIL (`languages.sh: No such file or directory` from `source_scripts`).

- [ ] **Step 3: Create `scripts/languages.sh` with the skeleton + `zig_target_triple`**

Create `scripts/languages.sh`:

```bash
#!/bin/bash
# Language toolchain installers (Linux + macOS only).
# Sourced by `dotfile`. Requires utils.sh, platform.sh, packages.sh already sourced.
set -eo pipefail

# Zig signing public key. Source: https://ziglang.org/download/  Copied: 2026-04-17
# Re-check periodically; the Zig project rarely rotates this but does occasionally.
ZIG_PUBKEY="<PASTE FROM TASK 0>"

# Map (uname -s, uname -m) to Zig's tarball arch slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
zig_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "x86_64-linux" ;;
    Linux/aarch64)       echo "aarch64-linux" ;;
    Linux/arm64)         echo "aarch64-linux" ;;
    Darwin/x86_64)       echo "x86_64-macos" ;;
    Darwin/arm64)        echo "aarch64-macos" ;;
    Darwin/aarch64)      echo "aarch64-macos" ;;
    *) fail "Unsupported platform for zig install: $os/$arch" ;;
  esac
}
```

(Replace `<PASTE FROM TASK 0>` with the actual key string recorded in Task 0.)

- [ ] **Step 4: Run tests, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add languages.sh skeleton and zig_target_triple"
```

---

## Task 3: Implement `zig_latest_stable`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# zig_latest_stable
# ---------------------------------------------------------------------------

test_zig_latest_stable_picks_highest() {
  # Stub jq presence and http_get_retry
  http_get_retry() { cat <<'JSON'
{"master": {"version": "0.15.0-dev"}, "0.13.0": {}, "0.14.1": {}, "0.12.0": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.14.1" "$result"
}

test_zig_latest_stable_skips_master() {
  http_get_retry() { cat <<'JSON'
{"master": {}, "0.10.0": {}}
JSON
  }
  export -f http_get_retry

  local result
  result="$(zig_latest_stable)"
  assert_equals "0.10.0" "$result"
}

test_zig_latest_stable_fails_on_empty() {
  http_get_retry() { echo '{}'; }
  export -f http_get_retry

  local exit_code=0
  ( zig_latest_stable ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: zig_latest_stable should fail on empty index" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 3 new tests FAIL with "command not found: zig_latest_stable" (or similar).

- [ ] **Step 3: Implement `zig_latest_stable` and `ensure_jq`**

Append to `scripts/languages.sh` (jq is needed by `zig_latest_stable`, so define `ensure_jq` first; we'll wire it into `install_zig` later):

```bash
# Install jq via the platform package manager if missing. Used by zig_latest_stable.
ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  info "jq not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y jq || fail "Failed to install jq" ;;
    arch)   sudo pacman -S --needed --noconfirm jq || fail "Failed to install jq" ;;
    mac)    brew install jq || fail "Failed to install jq" ;;
    *)      fail "Cannot install jq on this platform" ;;
  esac
  success "Installed jq"
}

# Print the highest stable Zig version from the official index.json.
# Skips the "master" key (development build).
zig_latest_stable() {
  local json
  json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"
  local version
  version="$(echo "$json" | jq -r '
    keys_unsorted
    | map(select(. != "master"))
    | sort_by(split(".") | map(tonumber? // 0))
    | last // empty
  ')" || fail "Failed to parse Zig index.json"
  if [[ -z "$version" ]]; then
    fail "No stable Zig version found in index.json"
  fi
  echo "$version"
}
```

Note: tests stub `http_get_retry` directly so they don't need `jq` to be installed in the test env... wait, actually `zig_latest_stable` does pipe the stub output into real `jq`. The test environment must have `jq` installed. The Docker image (Ubuntu 24.04 in `runner.sh`) does NOT include jq. We need to either (a) install jq in the Docker image or (b) stub jq too.

Choose (a) — it's simpler and tests stay realistic. Update `tests/bash/runner.sh` Dockerfile heredoc to add `jq` to the apt-get install line:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils git diffutils ca-certificates jq \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 4: Run tests on host (you have jq from `pacman -Qs jq` if it's there, otherwise install it)**

Verify jq is on the host first:
```bash
command -v jq || sudo pacman -S --needed --noconfirm jq
```

Run:
```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 8 PASS (5 from Task 2 + 3 new).

- [ ] **Step 5: Run tests in Docker to confirm Dockerfile change works**

```bash
bash tests/bash/runner.sh test_languages.sh
```
Expected: 8 PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh tests/bash/runner.sh
git commit -m "Add zig_latest_stable and ensure_jq helper"
```

---

## Task 4: Implement `zig_current_installed_version`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# zig_current_installed_version
# ---------------------------------------------------------------------------

test_zig_current_installed_version_none() {
  local result
  result="$(zig_current_installed_version)"
  assert_equals "" "$result"
}

test_zig_current_installed_version_ours_returns_version() {
  mkdir -p "$HOME/.local/zig-0.14.1"
  touch "$HOME/.local/zig-0.14.1/zig"
  ln -s "$HOME/.local/zig-0.14.1/zig" "$HOME/.local/bin/zig"

  local result
  result="$(zig_current_installed_version)"
  assert_equals "0.14.1" "$result"
}

test_zig_current_installed_version_foreign_returns_empty() {
  # Symlink points outside ~/.local/zig-*/
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/zig"
  ln -s "$HOME/elsewhere/zig" "$HOME/.local/bin/zig"

  local result
  result="$(zig_current_installed_version)"
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
# Print the currently-installed Zig version IF it was installed by this script.
# Returns empty string for: no install, foreign install (e.g., system zig).
# Detection rule: ~/.local/bin/zig must be a symlink whose target is
# ~/.local/zig-<version>/zig.
zig_current_installed_version() {
  local link="$HOME/.local/bin/zig"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  # Match $HOME/.local/zig-<version>/zig (use a parameter expansion check
  # rather than regex to stay portable across bash versions).
  local prefix="$HOME/.local/zig-"
  local suffix="/zig"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#$prefix}"
      middle="${middle%$suffix}"
      # Reject if middle still contains a slash (would mean nested dir)
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
Expected: 11 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add zig_current_installed_version"
```

---

## Task 5: Implement `ensure_minisign`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# ensure_minisign
# ---------------------------------------------------------------------------

test_ensure_minisign_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/minisign"
  chmod +x "$HOME/.local/bin/minisign"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_minisign 2>&1)
  # No "Installing minisign" line should appear
  if [[ "$output" == *"Installing minisign"* ]]; then
    echo "  FAILED: ensure_minisign should noop when minisign already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_minisign_dry_run_arch_logs_install() {
  DRY=true
  mock_uname Linux
  # Stub /etc/os-release detection — easier to override detect_platform directly
  detect_platform() { echo "arch"; }
  export -f detect_platform
  # Make sure minisign is NOT on PATH
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_debian_logs_install() {
  DRY=true
  detect_platform() { echo "debian"; }
  export -f detect_platform
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}

test_ensure_minisign_dry_run_mac_logs_install() {
  DRY=true
  detect_platform() { echo "mac"; }
  export -f detect_platform
  export PATH="/tmp/empty-$$:$HOME/.local/bin"
  rm -f "$HOME/.local/bin/minisign"

  local output
  output=$(ensure_minisign 2>&1)
  assert_contains "$output" "minisign not found"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 4 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Install minisign via the platform package manager if missing. Required for
# tarball signature verification.
ensure_minisign() {
  if command -v minisign >/dev/null 2>&1; then
    return 0
  fi
  info "minisign not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y minisign || fail "Failed to install minisign" ;;
    arch)   sudo pacman -S --needed --noconfirm minisign || fail "Failed to install minisign" ;;
    mac)    brew install minisign || fail "Failed to install minisign" ;;
    *)      fail "Cannot install minisign on this platform" ;;
  esac
  success "Installed minisign"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 15 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add ensure_minisign helper"
```

---

## Task 6: Implement `install_zig` (dry-run + skip-if-current paths)

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

The full mirror loop / signature verification / extraction logic is added here, but only the dry-run path and the "already installed" short-circuit are unit-testable. The verification logic is covered by the manual smoke test in Task 13.

- [ ] **Step 1: Write failing tests for the testable paths**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# install_zig
# ---------------------------------------------------------------------------

test_install_zig_dry_run() {
  DRY=true
  # Stub the lookup so we don't hit network. Pretend there is no install yet.
  zig_latest_stable() { echo "0.14.1"; }
  export -f zig_latest_stable
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_zig 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Finished"
  # No tarball should land on disk
  if [[ -e "$HOME/.local/zig-0.14.1" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_zig_already_installed_short_circuits() {
  # Pretend latest is 0.14.1 AND that 0.14.1 is already installed
  mkdir -p "$HOME/.local/zig-0.14.1"
  touch "$HOME/.local/zig-0.14.1/zig"
  ln -s "$HOME/.local/zig-0.14.1/zig" "$HOME/.local/bin/zig"

  zig_latest_stable() { echo "0.14.1"; }
  export -f zig_latest_stable
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_zig 2>&1)
  assert_contains "$output" "Already installed Zig 0.14.1"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 2 new tests FAIL.

- [ ] **Step 3: Implement `install_zig`**

Append to `scripts/languages.sh`:

```bash
# Install (or upgrade) Zig from the official community mirrors with full
# minisign signature verification + sha256 cross-check.
#
# Layout: extracts to ~/.local/zig-<version>/ and symlinks ~/.local/bin/zig.
# Skips if the target version is already installed (per zig_current_installed_version).
install_zig() {
  info "Installing Zig..."
  ensure_minisign
  ensure_jq

  local triple version
  triple="$(zig_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest stable Zig for $triple"
    success "Finished installing Zig (dry run)"
    return 0
  fi

  version="$(zig_latest_stable)"
  local tarball="zig-${triple}-${version}.tar.xz"

  local current
  current="$(zig_current_installed_version)"
  if [[ "$current" == "$version" ]]; then
    success "Already installed Zig $version"
    return 0
  fi

  # Cross-check: pull the expected sha256 from index.json for this triple.
  local index_json shasum
  index_json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"
  shasum="$(echo "$index_json" | jq -r --arg v "$version" --arg t "$triple" \
    '.[$v][$t].shasum // empty')"
  if [[ -z "$shasum" ]]; then
    fail "Could not find shasum for $version/$triple in index.json"
  fi

  # Mirror loop with verification
  local mirrors_text mirror tmpdir
  mirrors_text="$(http_get_retry "https://ziglang.org/download/community-mirrors.txt")" \
    || fail "Failed to fetch community-mirrors.txt"
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local got_it=false
  while IFS= read -r mirror; do
    [[ -z "$mirror" ]] && continue
    info "Trying mirror: $mirror"
    local tar_path="$tmpdir/$tarball"
    local sig_path="$tar_path.minisig"
    rm -f "$tar_path" "$sig_path"

    if ! curl -sfL "$mirror/$tarball?source=quando-dotfiles" -o "$tar_path"; then
      continue
    fi
    if ! curl -sfL "$mirror/$tarball.minisig?source=quando-dotfiles" -o "$sig_path"; then
      continue
    fi
    if ! minisign -V -P "$ZIG_PUBKEY" -m "$tar_path" -x "$sig_path" >/dev/null 2>&1; then
      info "Signature verification failed; trying next mirror"
      continue
    fi
    # Downgrade-attack guard: parse trusted comment for `file:` field
    local actual
    actual="$(grep -m1 '^trusted comment:' "$sig_path" \
      | sed -n 's/.*file:\([^[:space:]]*\).*/\1/p')"
    if [[ "$actual" != "$tarball" ]]; then
      info "Signed filename mismatch (got '$actual'); trying next mirror"
      continue
    fi
    # Defense-in-depth sha256 check
    local got_sha
    got_sha="$(sha256sum "$tar_path" | awk '{print $1}')"
    if [[ "$got_sha" != "$shasum" ]]; then
      info "sha256 mismatch; trying next mirror"
      continue
    fi
    got_it=true
    break
  done < <(echo "$mirrors_text" | shuf)

  if [[ "$got_it" != "true" ]]; then
    fail "Could not fetch a verified Zig tarball from any mirror"
  fi

  # Extract to a temp subdir, then move to ~/.local/zig-<version>/
  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tmpdir/$tarball" -C "$extract_dir" \
    || fail "Failed to extract Zig tarball"
  local extracted
  extracted="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$extracted" ]] || fail "Tarball extracted to an unexpected layout"

  local target_dir="$HOME/.local/zig-$version"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Zig into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/zig" "$HOME/.local/bin/zig" \
    || fail "Failed to create ~/.local/bin/zig symlink"

  # Clean up old versions (any ~/.local/zig-*/ that isn't the current one)
  local old
  for old in "$HOME"/.local/zig-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Zig $version"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 17 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add install_zig with mirror loop and signature verification"
```

---

## Task 7: Implement `update_zig`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# update_zig
# ---------------------------------------------------------------------------

test_update_zig_no_op_when_not_installed() {
  # No ~/.local/bin/zig at all
  local output
  output=$(update_zig 2>&1)
  assert_equals "" "$output"
}

test_update_zig_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/zig"
  ln -s "$HOME/elsewhere/zig" "$HOME/.local/bin/zig"

  local output
  output=$(update_zig 2>&1)
  assert_equals "" "$output"
}

test_update_zig_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/zig-0.14.0"
  touch "$HOME/.local/zig-0.14.0/zig"
  ln -s "$HOME/.local/zig-0.14.0/zig" "$HOME/.local/bin/zig"

  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(update_zig 2>&1)
  assert_contains "$output" "Installing Zig"
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
# Update Zig — but only if it was installed by this script. Foreign installs
# (system, brew, scoop) are left alone.
update_zig() {
  local current
  current="$(zig_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_zig
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 20 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add update_zig"
```

---

## Task 8: Implement `install_languages` umbrella

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# install_languages
# ---------------------------------------------------------------------------

test_install_languages_dry_run() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages 2>&1)
  assert_contains "$output" "Installing Zig"
}

test_install_languages_zig_only_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_languages zig 2>&1)
  assert_contains "$output" "Installing Zig"
}

test_install_languages_unknown_fails() {
  local exit_code=0
  ( install_languages java ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: install_languages should fail on unknown language" >> "$ERROR_FILE"
  fi
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
# Umbrella: install all languages, or just one if specified.
# Usage: install_languages [LANG]
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig ;;
    zig)    install_zig ;;
    *)      fail "Unknown language: $target" ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 23 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add install_languages umbrella"
```

---

## Task 9: Implement `update_languages`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing test**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# update_languages
# ---------------------------------------------------------------------------

test_update_languages_dry_run_no_install() {
  DRY=true
  # No zig install present → update_zig is a no-op → no output
  local output
  output=$(update_languages 2>&1)
  assert_equals "" "$output"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 1 new test FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Update every language that this script previously installed.
update_languages() {
  update_zig
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 24 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add update_languages umbrella"
```

---

## Task 10: Wire `languages` into the `dotfile` CLI

**Files:**
- Modify: `dotfile`

- [ ] **Step 1: Source the new script and add `update_languages` to `update`**

Edit `dotfile`. After line 46 (`source "$SCRIPTS_DIR/obsidian.sh"`), add:

```bash
source "$SCRIPTS_DIR/languages.sh"
```

In the `case "${1:-all}"` dispatch block, change the `update)` arm to also call `update_languages`. Replace:

```bash
update) update_packages ;;
```

with:

```bash
update)
  update_packages
  update_languages
  ;;
```

Add a new dispatch arm before the catch-all `*)`:

```bash
languages) install_languages "${2:-}" ;;
```

- [ ] **Step 2: Update the `usage` heredoc**

In the `usage` function, add a `languages` line in the Commands block. Replace:

```
  obsidian    Set up Obsidian headless sync (Linux only; runs separately from 'all')
  verify      Verify installation
```

with:

```
  obsidian    Set up Obsidian headless sync (Linux only; runs separately from 'all')
  languages [LANG]  Install language toolchains (currently: zig). LANG selects one.
  verify      Verify installation
```

- [ ] **Step 3: Smoke-test the CLI manually**

```bash
bash ./dotfile --help
```
Expected: output contains "languages [LANG]".

```bash
bash ./dotfile --dry languages
```
Expected: exits 0 with `Installing Zig` log line.

```bash
bash ./dotfile --dry languages zig
```
Expected: exits 0 with `Installing Zig` log line.

```bash
bash ./dotfile --dry update
```
Expected: exits 0 (no zig install present → update_languages is silent on languages, but `update_packages` runs its dry path).

- [ ] **Step 4: Commit**

```bash
git add dotfile
git commit -m "Wire languages subcommand into dotfile CLI"
```

---

## Task 11: Add CLI dispatch tests

**Files:**
- Modify: `tests/bash/test_cli.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_cli.sh`:

```bash
test_languages_command_in_help() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  assert_contains "$output" "languages"
}

test_dry_run_languages_command() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages
}

test_dry_run_languages_zig() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages zig
}
```

- [ ] **Step 2: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_cli.sh
```
Expected: all `test_cli.sh` tests pass, including the 3 new ones. (They pass immediately because Task 10 already shipped the CLI dispatch — this task just adds the tests.)

If any of the 3 new tests fails, that's a real regression in the dispatch wiring from Task 10 — fix the dispatch, don't soften the test.

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_cli.sh
git commit -m "Add CLI dispatch tests for languages subcommand"
```

---

## Task 12: Full test sweep

**Files:** none (verification only)

- [ ] **Step 1: Run the full bash test suite in Docker**

```bash
bash tests/bash/runner.sh
```
Expected: all tests PASS, no regressions in any pre-existing file.

- [ ] **Step 2: If anything fails, fix the underlying cause**

Do NOT loosen test assertions. The most likely failure modes:
- `mock_uname` rework in Task 1 broke an existing platform test → revisit the rewrite
- Docker image missing `jq` → confirm the Dockerfile change from Task 3 landed

- [ ] **Step 3: No commit**

This task ends when the suite is green. No code changed.

---

## Task 13: Manual smoke test (Arch + macOS)

**Files:** none (manual verification)

The mirror loop, real signature verification, sha256 check, atomic extraction, and old-version cleanup can't be unit-tested. Run these manually before considering the feature done.

- [ ] **Step 1: Fresh install on Arch**

```bash
rm -rf "$HOME"/.local/zig-* "$HOME/.local/bin/zig"
bash ./dotfile languages zig
"$HOME/.local/bin/zig" version
```
Expected: prints the latest stable version (matches the version listed at https://ziglang.org/download/).

- [ ] **Step 2: Re-install is idempotent**

```bash
bash ./dotfile languages zig
```
Expected: log line `Already installed Zig <version>`. Returns immediately. No new files created (compare `ls -la $HOME/.local/zig-*` before/after).

- [ ] **Step 3: Force re-install path works**

```bash
rm -rf "$HOME"/.local/zig-* "$HOME/.local/bin/zig"
bash ./dotfile languages
"$HOME/.local/bin/zig" version
```
Expected: same as step 1 (umbrella `languages` with no arg also installs zig).

- [ ] **Step 4: Update is a no-op on the latest version**

```bash
bash ./dotfile update
```
Expected: `update_packages` runs as before, `update_zig` calls `install_zig` which short-circuits with `Already installed Zig <version>`.

- [ ] **Step 5: Update ignores foreign installs**

Pretend system zig is the active one:
```bash
mv "$HOME/.local/bin/zig" "$HOME/.local/bin/zig.ours"
ln -s /tmp/fake-system-zig "$HOME/.local/bin/zig"
bash ./dotfile update 2>&1 | grep -i zig || echo "(no zig output — as expected)"
mv "$HOME/.local/bin/zig.ours" "$HOME/.local/bin/zig"
rm -f /tmp/fake-system-zig "$HOME/.local/bin/zig"  # clean up the foreign-install simulation
ln -sfn "$HOME"/.local/zig-*/zig "$HOME/.local/bin/zig"
```
Expected: `update` output contains nothing about Zig.

- [ ] **Step 6: Downgrade-attack guard works**

This requires hand-editing a `.minisig` file's `file:` trusted-comment field and forcing the script to use it. Skip if you don't want to set up the test rig — the unit-level guarantees from `install_zig`'s `actual != tarball` check are obvious from code review.

- [ ] **Step 7: Repeat steps 1–4 on macOS**

Run the same sequence on a Mac (with `brew` already configured). Expected: same behaviour. `ensure_minisign` will install `minisign` via brew on first run.

- [ ] **Step 8: No commit, no PR yet**

Once smoke tests pass, the feature is done. Open a PR or merge as you prefer.

---

## Self-review notes

- **Spec coverage:** All sections of the spec (CLI surface, install layout, every function in the inventory, update flow integration, help text, every test in the test plan, manual smoke test) map to tasks above. The `ensure_jq` addition is the only deviation, called out at the top.
- **Placeholders:** None remain. Task 0 has the `<PASTE FROM TASK 0>` marker but Task 0 itself is the step that resolves it before Task 2 runs.
- **Type / name consistency:** Function names match across tasks. `ZIG_PUBKEY` consistent. Symlink layout (`~/.local/zig-<version>/zig` → `~/.local/bin/zig`) consistent across `zig_current_installed_version`, `install_zig`, and `update_zig` tests.
