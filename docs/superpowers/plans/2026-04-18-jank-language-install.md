# Jank Language Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Jank as the fourth language under `dotfile languages [LANG]`. Linux + macOS only with strict OS subset (Apple Silicon mac, Ubuntu, Arch). Lenient umbrella behaviour: unsupported platforms get a visible "Skipping Jank" message and exit 0.

**Architecture:** Append to `scripts/languages.sh`. Unlike Zig/Odin/Gleam, no GitHub binary download — install dispatches to the platform PM (brew tap, apt PPA, or AUR via the existing `setup_yay` helper). Trust = the platform PM's signing model. Jank has no `--version` flag, so version detection collapses to "is jank installed at all".

**Tech Stack:** Bash 4+ on Linux/macOS. Reuses `info`/`success`/`fail` from `utils.sh`, `detect_platform` from `platform.sh`, `setup_yay` from `packages.sh`. No PowerShell changes (Jank doesn't support Windows).

**Spec:** `docs/superpowers/specs/2026-04-18-jank-language-install-design.md`.

**Pre-execution baseline:**
- Bash on host (`bash tests/bash/runner.sh --no-docker`): 213 passed / 0 failed on `main`.
- Bash in worktree: 212 passed / 1 failed (1 = pre-existing path-brittle `test_dotfile_symlinks_command_mac`, unrelated).
- Bash in Docker: 213 passed / 0 failed.
- After this plan: ~228 bash (~15 new tests).

**No PowerShell changes** — Jank doesn't support Windows. PS test count stays at 61/1 (the 1 = pre-existing AddToUserPath quirk on Linux pwsh).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Modify | Add `jank_check_platform`, `jank_current_installed_version`, `_install_jank_ppa`, `install_jank`, `update_jank`. Extend `install_languages` and `update_languages`. |
| `tests/bash/test_languages.sh` | Modify | ~15 new/changed tests. |
| `tests/bash/test_cli.sh` | Modify | 1 new test for `dotfile --dry languages jank`. |
| `dotfile` | Modify | Update `usage` text: `(zig, odin, gleam)` → `(zig, odin, gleam, jank)`. |
| `CLAUDE.md` | Modify | Update existing `dotfile languages [LANG]` line to include `jank`. |

No changes to: `dotfile.ps1`, `tests/powershell/*`, `tests/bash/runner.sh`, `tests/bash/helpers.sh`, `scripts/packages.sh`, `scripts/platform.sh`.

---

## Reused stubbing patterns

**Bash:** Shadow real functions inside the test body and `export -f` so the override propagates into subshells:

```bash
test_xyz() {
  detect_platform() { echo "arch"; }
  export -f detect_platform
  ...
}
```

For `command -v <bin>` checks where the real binary may be present on the dev host, shadow `command`:

```bash
command() {
  if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then
    return 1   # pretend not found
  fi
  builtin command "$@"
}
export -f command
```

To simulate "jank IS on PATH" without installing it, drop a fake stub:

```bash
echo '#!/bin/bash' > "$HOME/.local/bin/jank"
chmod +x "$HOME/.local/bin/jank"
export PATH="$HOME/.local/bin:$PATH"
```

---

## Task 1: `jank_check_platform`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

The first new function. Returns 0 if Jank can be installed on this host, non-zero otherwise. **Does not call `fail`** — caller decides whether to error or skip. Accepts an optional `$1` to override the `/etc/os-release` ID lookup (lets tests inject "ubuntu" or "debian" without touching the real file).

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# jank_check_platform
# ---------------------------------------------------------------------------

test_jank_check_platform_mac_arm64_succeeds() {
  mock_uname Darwin
  mock_uname_m arm64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  jank_check_platform
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_mac_x86_64_returns_nonzero() {
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local rc=0
  jank_check_platform || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on Intel mac" >> "$ERROR_FILE"
  fi
}

test_jank_check_platform_arch_succeeds() {
  detect_platform() { echo "arch"; }
  export -f detect_platform

  jank_check_platform
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_ubuntu_via_arg_succeeds() {
  detect_platform() { echo "debian"; }
  export -f detect_platform

  jank_check_platform ubuntu
  local rc=$?
  assert_equals "0" "$rc"
}

test_jank_check_platform_debian_via_arg_returns_nonzero() {
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local rc=0
  jank_check_platform debian || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on plain Debian" >> "$ERROR_FILE"
  fi
}

test_jank_check_platform_unknown_returns_nonzero() {
  detect_platform() { echo "unknown"; }
  export -f detect_platform

  local rc=0
  jank_check_platform || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  FAILED: jank_check_platform should return non-zero on unknown platform" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 6 new tests FAIL with "jank_check_platform: command not found".

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Returns 0 if jank can be installed on this platform, non-zero otherwise.
# Does NOT call fail — caller decides whether to error or skip.
#
# Optional $1: override the /etc/os-release ID lookup (for tests).
jank_check_platform() {
  local id_override="${1:-}"
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    mac)
      [[ "$(uname -m)" == "arm64" ]] || return 1
      ;;
    arch) ;;  # supported
    debian)
      # detect_platform groups Ubuntu under "debian"; jank's PPA targets Ubuntu only.
      local ID="$id_override"
      if [[ -z "$ID" && -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
      fi
      [[ "${ID:-}" == "ubuntu" ]] || return 1
      ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 6 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add jank_check_platform"
```

---

## Task 2: `jank_current_installed_version`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

Detects whether Jank is installed at all. Different shape from `*_current_installed_version` for Zig/Odin/Gleam — returns the sentinel `installed` rather than a version tag (Jank has no `--version` flag).

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# jank_current_installed_version
# ---------------------------------------------------------------------------

test_jank_current_installed_version_none() {
  # Shadow command so `command -v jank` reports not found regardless of host.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local result
  result="$(jank_current_installed_version)"
  assert_equals "" "$result"
}

test_jank_current_installed_version_present() {
  # Drop a fake jank on PATH.
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local result
  result="$(jank_current_installed_version)"
  assert_equals "installed" "$result"
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
# Returns "installed" if jank is on PATH, empty otherwise.
# Jank has no --version flag, so we can't track precise versions like with
# Zig/Odin/Gleam. The string "installed" is a sentinel value.
jank_current_installed_version() {
  command -v jank >/dev/null 2>&1 && echo "installed"
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
git commit -m "Add jank_current_installed_version"
```

---

## Task 3: `install_jank` (and the `_install_jank_ppa` helper)

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

The full install dispatch. Implements:
- Lenient skip on unsupported platforms (visible "Skipping Jank" + exit 0).
- Dry-run gate before any PM call.
- Skip-if-already-installed.
- Per-platform install via brew tap, AUR, or apt+PPA.
- The PPA setup helper `_install_jank_ppa` for Ubuntu (idempotent — only runs if `/etc/apt/sources.list.d/jank.list` is missing).

Real PM calls aren't unit-tested; manual smoke covers them.

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# install_jank
# ---------------------------------------------------------------------------

test_install_jank_unsupported_platform_skips() {
  # Mocked Intel mac: jank_check_platform returns non-zero.
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output rc=0
  output=$(install_jank 2>&1) || rc=$?
  assert_equals "0" "$rc"
  assert_contains "$output" "Skipping Jank"
}

test_install_jank_dry_run_arch() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(install_jank 2>&1)
  assert_contains "$output" "Installing Jank"
  assert_contains "$output" "Would install Jank"
  assert_contains "$output" "Finished installing Jank (dry run)"
}

test_install_jank_already_installed_short_circuits() {
  detect_platform() { echo "arch"; }
  export -f detect_platform
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(install_jank 2>&1)
  assert_contains "$output" "Already installed Jank"
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
# Idempotent jank PPA setup (Ubuntu only — caller enforces). One-time
# GPG key + sources.list addition + apt update. No-ops if jank.list exists.
_install_jank_ppa() {
  if [[ -f /etc/apt/sources.list.d/jank.list ]]; then
    return 0
  fi
  info "Setting up jank PPA..."
  sudo apt install -y curl gnupg || fail "Failed to install curl + gnupg"
  curl -sf "https://ppa.jank-lang.org/KEY.gpg" \
    | gpg --dearmor \
    | sudo tee /etc/apt/trusted.gpg.d/jank.gpg >/dev/null \
    || fail "Failed to import jank PPA signing key"
  sudo curl -sfo /etc/apt/sources.list.d/jank.list "https://ppa.jank-lang.org/jank.list" \
    || fail "Failed to fetch jank PPA sources list"
  sudo apt update || fail "Failed to apt update after jank PPA setup"
}

# Install Jank via the platform package manager.
# Lenient on unsupported platforms: visible skip + exit 0.
install_jank() {
  info "Installing Jank..."
  if ! jank_check_platform; then
    info "Skipping Jank: not supported on this platform — see https://book.jank-lang.org/getting-started/01-installation.html"
    success "Finished (skipped Jank)"
    return 0
  fi

  if [[ "$DRY" == "true" ]]; then
    info "Would install Jank via the platform package manager"
    success "Finished installing Jank (dry run)"
    return 0
  fi

  if [[ -n "$(jank_current_installed_version)" ]]; then
    success "Already installed Jank"
    return 0
  fi

  case "$(detect_platform)" in
    mac)
      brew install jank-lang/jank/jank || fail "Failed to install jank via brew"
      ;;
    arch)
      setup_yay  # idempotent helper from packages.sh
      yay -S --needed --noconfirm jank-bin || fail "Failed to install jank-bin via yay"
      ;;
    debian)  # Ubuntu only — jank_check_platform already enforced
      _install_jank_ppa
      sudo apt install -y jank || fail "Failed to install jank via apt"
      ;;
  esac
  success "Installed Jank"
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
git commit -m "Add install_jank with platform PM dispatch"
```

---

## Task 4: `update_jank`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

Quieter than `install_jank` on unsupported platforms — silent no-op rather than visible skip (matches the existing `update_zig`/`update_odin`/`update_gleam` "silent if nothing to do" pattern).

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# update_jank
# ---------------------------------------------------------------------------

test_update_jank_no_op_when_not_installed() {
  detect_platform() { echo "arch"; }
  export -f detect_platform
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "jank" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command

  local output
  output=$(update_jank 2>&1)
  assert_equals "" "$output"
}

test_update_jank_unsupported_platform_no_op() {
  mock_uname Darwin
  mock_uname_m x86_64
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output rc=0
  output=$(update_jank 2>&1) || rc=$?
  assert_equals "0" "$rc"
  assert_equals "" "$output"
}

test_update_jank_dry_run_when_installed() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform
  echo '#!/bin/bash' > "$HOME/.local/bin/jank"
  chmod +x "$HOME/.local/bin/jank"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(update_jank 2>&1)
  assert_contains "$output" "Updating Jank"
  assert_contains "$output" "Would update Jank"
  assert_contains "$output" "Finished updating Jank (dry run)"
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
# Update Jank via the platform package manager. Silent no-op on unsupported
# platforms or when jank isn't installed.
update_jank() {
  jank_check_platform || return 0
  [[ -z "$(jank_current_installed_version)" ]] && return 0
  info "Updating Jank..."
  if [[ "$DRY" == "true" ]]; then
    info "Would update Jank via the platform package manager"
    success "Finished updating Jank (dry run)"
    return 0
  fi
  case "$(detect_platform)" in
    mac)    brew update && brew reinstall jank-lang/jank/jank || fail "Failed to update jank via brew" ;;
    arch)   yay -Syy --noconfirm && yay -S --noconfirm jank-bin || fail "Failed to update jank via yay" ;;
    debian) sudo apt update && sudo apt reinstall -y jank || fail "Failed to update jank via apt" ;;
  esac
  success "Updated Jank"
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
git commit -m "Add update_jank"
```

---

## Task 5: Extend bash umbrellas

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Update existing tests + add a new one**

In `tests/bash/test_languages.sh`, REPLACE the body of `test_install_languages_all_arg`:

```bash
test_install_languages_all_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages all 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Installing Jank"
}
```

REPLACE `test_install_languages_dry_run`:

```bash
test_install_languages_dry_run() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Installing Jank"
}
```

APPEND a new test:

```bash
test_install_languages_jank_only_arg() {
  DRY=true
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(install_languages jank 2>&1)
  assert_contains "$output" "Installing Jank"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages jank should not run Zig" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Odin"* ]]; then
    echo "  FAILED: install_languages jank should not run Odin" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Gleam"* ]]; then
    echo "  FAILED: install_languages jank should not run Gleam" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: at least the new `_jank_only_arg` test FAILs (no `jank)` arm yet); the updated `_all_arg` and `_dry_run` tests also FAIL because the umbrella doesn't yet call `install_jank`.

- [ ] **Step 3: Implement**

Edit `install_languages` in `scripts/languages.sh`. Replace its body with:

```bash
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig; install_odin; install_gleam; install_jank ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    gleam)  install_gleam ;;
    jank)   install_jank ;;
    *)      fail "Unknown language: $target" ;;
  esac
}
```

Replace `update_languages`:

```bash
update_languages() {
  update_zig
  update_odin
  update_gleam
  update_jank
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add Jank to install_languages and update_languages umbrellas"
```

---

## Task 6: Add CLI dispatch test

**Files:**
- Modify: `tests/bash/test_cli.sh`

The CLI itself doesn't need a code change — `dotfile`'s existing `languages) install_languages "${2:-}" ;;` arm already routes `jank` through. But we need a regression test that locks the behaviour in.

- [ ] **Step 1: Append the test**

Append to `tests/bash/test_cli.sh`:

```bash
test_dry_run_languages_jank() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages jank
}
```

- [ ] **Step 2: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_cli.sh
```
Expected: all `test_cli.sh` tests pass, including the new one. (Passes immediately because Task 5 already wired the umbrella.)

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_cli.sh
git commit -m "Add CLI dispatch test for languages jank"
```

---

## Task 7: Update `dotfile` usage text + `CLAUDE.md`

**Files:**
- Modify: `dotfile`
- Modify: `CLAUDE.md`

Two one-line documentation edits.

- [ ] **Step 1: Update `dotfile` usage**

Find the line in `dotfile`'s `usage` heredoc:

```
  languages [LANG]  Install language toolchains (zig, odin, gleam). LANG selects one.
```

Replace with:

```
  languages [LANG]  Install language toolchains (zig, odin, gleam, jank). LANG selects one.
```

- [ ] **Step 2: Update `CLAUDE.md`**

Find:

```
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam)
```

Replace with:

```
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam, jank)
```

- [ ] **Step 3: Verify**

```bash
grep -n 'languages \[LANG\]' dotfile CLAUDE.md
```
Expected: both updated lines mention `jank`.

- [ ] **Step 4: Commit**

```bash
git add dotfile CLAUDE.md
git commit -m "Document Jank in usage text and CLAUDE.md"
```

---

## Task 8: Full bash test sweep

**Files:** none (verification only)

- [ ] **Step 1: Run --no-docker**

```bash
bash tests/bash/runner.sh --no-docker
```
Expected: ~228 passed / 1 failed (1 is the pre-existing `test_dotfile_symlinks_command_mac` worktree-path-brittle test).

- [ ] **Step 2: Run Docker**

```bash
bash tests/bash/runner.sh
```
Expected: ~228 passed / 0 failed.

- [ ] **Step 3: Run PowerShell suite to confirm no incidental damage**

```bash
pwsh tests/powershell/runner.ps1
```
Expected: 61 passed / 1 failed (unchanged from baseline — Jank work doesn't touch PS).

- [ ] **Step 4: If anything fails, fix the underlying cause**

Most likely failure modes:
- A test that didn't shadow `command` correctly leaks to a real `command -v` call.
- A stub of `detect_platform` from one test leaking into another (subshell isolation should prevent this — if it doesn't, suspect an `export -f` that escaped).
- Umbrella test didn't account for `install_jank`'s skip-message vs install-message variants depending on host platform.

Do NOT loosen test assertions to make them pass.

- [ ] **Step 5: No commit**

This task ends when all three runs are green.

---

## Task 9: Manual smoke test (Arch host)

**Files:** none (manual verification only)

The PM-dispatch path can't be unit-tested. Run these manually before considering done.

**Note:** Will require sudo for `setup_yay` (if yay isn't already installed) AND for the `yay -S jank-bin` package install (yay invokes pacman under the hood). The user runs the smoke step in their own terminal because Claude's TTY-less shell can't accept sudo prompts.

- [ ] **Step 1: Fresh install**

```bash
bash ./dotfile languages jank
command -v jank && jank --help 2>&1 | head -5
```

Expected:
- `setup_yay` runs (or noops if yay is already on PATH).
- `yay -S --needed --noconfirm jank-bin` builds + installs jank-bin.
- `command -v jank` succeeds.
- `jank --help` (or whatever flag prints something) confirms it runs.

If `jank --help` doesn't exist either, just confirm `command -v jank` finds it.

- [ ] **Step 2: Re-install is idempotent**

```bash
bash ./dotfile languages jank
```

Expected: `Already installed Jank`. Returns instantly. No new yay activity.

- [ ] **Step 3: Update**

```bash
bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_jank'
```

Expected: `Updating Jank...` then `yay -Syy && yay -S jank-bin` runs (slow — queries AUR). On success: `Updated Jank`.

- [ ] **Step 4: Umbrella runs all four**

```bash
bash ./dotfile languages
```

Expected: `Installing Zig... / Already installed Zig <ztag>` + `Installing Odin... / Already installed Odin <otag>` + `Installing Gleam... / Already installed Gleam <gtag>` + `Installing Jank... / Already installed Jank`.

- [ ] **Step 5: Mac smoke deferred** (no Mac available).
- [ ] **Step 6: Ubuntu smoke deferred** (no Ubuntu host available).
- [ ] **Step 7: No commit**

Once steps 1–4 pass, the bash side is done.

---

## Self-review notes

- **Spec coverage:** Every function in the spec maps to a task. Bash inventory (`jank_check_platform`, `jank_current_installed_version`, `_install_jank_ppa`, `install_jank`, `update_jank`) → Tasks 1, 2, 3, 4. Bash umbrellas → Task 5. CLI test → Task 6. `dotfile` usage + CLAUDE.md → Task 7. Bash sweep → Task 8. Smoke → Task 9.
- **Placeholder scan:** No "TBD" / "implement later" / "appropriate error handling". Every step has runnable code, exact commands, or concrete edits.
- **Type / name consistency:** `jank_check_platform`, `jank_current_installed_version`, `_install_jank_ppa`, `install_jank`, `update_jank` consistent across tasks. The sentinel string `"installed"` is used identically in `jank_current_installed_version`'s implementation and its test. The `id_override` parameter name is used identically in `jank_check_platform`'s spec, implementation, and tests.
- **One thing worth flagging during execution:** Task 5 changes existing tests (`_install_languages_all_arg`, `_install_languages_dry_run`). On a host where Jank IS installable (Arch in our case), the new "Installing Jank" assertion will pass. On a host where Jank is NOT installable (e.g., the CI Docker container which is Ubuntu 24.04 — that's actually supported), `install_jank` would attempt the PPA setup. **But these tests run with `DRY=true`**, which short-circuits before any PM call, so the assertion holds regardless of platform. Confirmed safe.
