# PowerShell (pwsh) Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install PowerShell (`pwsh`) as part of the default `dotfile packages` flow on Debian/Ubuntu, Arch, and macOS. On Arch, bootstrap `yay` (AUR helper) first so `powershell-bin` can be pulled from the AUR.

**Architecture:** Add `setup_yay` and `setup_pwsh` to `scripts/packages.sh`. Wire `setup_pwsh` into `install_debian`, `install_arch`, `update_debian`, `update_arch` (mirroring the `setup_neovim` / `setup_lazygit` / `setup_zoxide` pattern). Add `setup_yay` to `install_arch` before `setup_pwsh`. Add `powershell` to `MAC_BREW_CASKS` — brew handles install + update automatically. Add `pwsh` to `REQUIRED_TOOLS` in `scripts/verify.sh`.

**Tech Stack:** Bash on Linux/macOS. Reuses `http_get_retry`, `is_mac`, `detect_platform`, `info`, `success`, `fail` from the existing scripts. No new external tools; `setup_yay` uses `git` + `makepkg` (already available on Arch via `base-devel`).

**Spec:** `docs/superpowers/specs/2026-04-18-pwsh-install-design.md`.

**Pre-execution baseline:** 180 tests passing on `main`. After this plan: ~188 passing (8 new tests across the tasks below).

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/packages.sh` | Modify | Add `setup_yay` and `setup_pwsh`. Extend `install_debian`, `install_arch`, `update_debian`, `update_arch`. Add `powershell` to `MAC_BREW_CASKS`. |
| `scripts/verify.sh` | Modify | Add `pwsh` to `REQUIRED_TOOLS`. |
| `tests/bash/test_packages.sh` | Modify | Add tests for `setup_yay` (dry-run, already-installed) and `setup_pwsh` (dry-run debian, dry-run arch, skips-on-mac, already-installed, update-dry-run, update-does-not-skip). |

No changes to `dotfile`, `dotfile.ps1`, `tests/bash/runner.sh`, `tests/bash/helpers.sh`, `tests/bash/test_verify.sh`, or `tests/bash/test_cli.sh`.

---

## Reused test stubbing pattern

Same shadowing idiom the rest of the suite uses — redefine a helper inside the test body. Tests run in a subshell (via `$(...)`) so the override is automatically scoped.

```bash
test_xyz() {
  detect_platform() { echo "arch"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)
  assert_contains "$output" "pwsh"
}
```

---

## Task 1: `setup_yay` (Arch AUR helper bootstrap)

**Files:**
- Modify: `scripts/packages.sh`
- Modify: `tests/bash/test_packages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_packages.sh` after the last existing test:

```bash
# ---------------------------------------------------------------------------
# setup_yay
# ---------------------------------------------------------------------------

test_setup_yay_dry_run() {
  DRY=true
  local output
  output=$(setup_yay 2>&1)

  assert_contains "$output" "yay"
  assert_contains "$output" "Finished yay"
}

test_setup_yay_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/yay"
  chmod +x "$HOME/.local/bin/yay"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_yay 2>&1)

  assert_contains "$output" "Already installed yay"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: `test_setup_yay_dry_run` and `test_setup_yay_already_installed` fail with "setup_yay: command not found" (or similar).

- [ ] **Step 3: Add `setup_yay` to `scripts/packages.sh`**

Insert after `setup_fdfind` (before the `DEBIAN_PACKAGES` array declaration):

```bash
# Bootstrap yay (AUR helper) on Arch. Clones yay-bin from the AUR and builds
# it with makepkg. Idempotent: no-op if yay is already on PATH.
# Usage: setup_yay
function setup_yay {
  info "Installing yay..."
  if [[ "$DRY" == "false" ]]; then
    if command -v yay >/dev/null 2>&1; then
      info "Already installed yay"
      success "Finished yay"
      return
    fi
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      fail "setup_yay must not run as root (makepkg refuses root)"
    fi
    command -v git >/dev/null 2>&1 || fail "git required for setup_yay"
    command -v makepkg >/dev/null 2>&1 || fail "makepkg required for setup_yay (install base-devel)"

    local build_dir="/tmp/yay-bin"
    rm -rf "$build_dir"
    git clone https://aur.archlinux.org/yay-bin.git "$build_dir" \
      || fail "Failed to clone yay-bin AUR repo"
    (cd "$build_dir" && makepkg -si --noconfirm) \
      || fail "Failed to build/install yay-bin"
    rm -rf "$build_dir"
  fi
  success "Finished yay"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all `setup_yay` tests pass. Other tests still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Add setup_yay to bootstrap AUR helper on Arch"
```

---

## Task 2: `setup_pwsh` — platform dispatch + Mac skip path

This task establishes the function skeleton and the Mac no-op branch. The Debian and Arch branches are filled in in Tasks 3 and 4.

**Files:**
- Modify: `scripts/packages.sh`
- Modify: `tests/bash/test_packages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_packages.sh` after the `setup_yay` tests:

```bash
# ---------------------------------------------------------------------------
# setup_pwsh
# ---------------------------------------------------------------------------

test_setup_pwsh_skips_on_mac() {
  detect_platform() { echo "mac"; }
  DRY=false
  local output
  output=$(setup_pwsh 2>&1)

  # Mac path uses brew casks via install_mac; setup_pwsh itself is a no-op.
  assert_equals "" "$output"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: `test_setup_pwsh_skips_on_mac` fails with "setup_pwsh: command not found".

- [ ] **Step 3: Add `setup_pwsh` skeleton to `scripts/packages.sh`**

Insert after `setup_yay`:

```bash
# Install or update pwsh (PowerShell 7+). Dispatches by platform:
#   - debian: Microsoft apt repo via packages-microsoft-prod.deb
#   - arch:   yay -S powershell-bin (AUR)
#   - mac:    no-op (handled by MAC_BREW_CASKS)
# Usage: setup_pwsh [--update]
function setup_pwsh {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true

  local platform
  platform="$(detect_platform)"

  case "$platform" in
    mac) return ;;
    debian|arch) ;;
    *) return ;;
  esac

  info "${update:+Updating}${update:- Installing} pwsh..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v pwsh >/dev/null 2>&1; then
      info "Already installed pwsh"
      success "Finished pwsh"
      return
    fi
    case "$platform" in
      debian) _setup_pwsh_debian "$update" ;;
      arch)   _setup_pwsh_arch "$update" ;;
    esac
  fi
  success "Finished pwsh"
}

# Placeholder branches — filled in by later tasks.
_setup_pwsh_debian() { :; }
_setup_pwsh_arch() { :; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: `test_setup_pwsh_skips_on_mac` passes. No regressions.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Add setup_pwsh skeleton with Mac no-op branch"
```

---

## Task 3: `setup_pwsh` — Debian/Ubuntu branch

**Files:**
- Modify: `scripts/packages.sh`
- Modify: `tests/bash/test_packages.sh`

- [ ] **Step 1: Write failing tests**

Append after the existing `setup_pwsh` test:

```bash
test_setup_pwsh_dry_run_debian() {
  detect_platform() { echo "debian"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}

test_setup_pwsh_already_installed() {
  detect_platform() { echo "debian"; }
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/pwsh"
  chmod +x "$HOME/.local/bin/pwsh"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "Already installed pwsh"
}

test_setup_pwsh_update_dry_run() {
  detect_platform() { echo "debian"; }
  DRY=true
  local output
  output=$(setup_pwsh --update 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}

test_setup_pwsh_update_does_not_skip() {
  detect_platform() { echo "debian"; }
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/pwsh"
  chmod +x "$HOME/.local/bin/pwsh"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_pwsh --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run tests to verify they pass**

All four tests above use `DRY=true` or rely on the `command -v pwsh` fast-path, neither of which reaches `_setup_pwsh_debian`. They should already pass against the skeleton from Task 2.

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all four new tests pass.

- [ ] **Step 3: Replace the `_setup_pwsh_debian` placeholder in `scripts/packages.sh`**

Find:

```bash
# Placeholder branches — filled in by later tasks.
_setup_pwsh_debian() { :; }
```

Replace `_setup_pwsh_debian` with:

```bash
# Install or update pwsh on Debian/Ubuntu via Microsoft's apt repo.
# $1 = "true" for --update mode (skip repo bootstrap).
_setup_pwsh_debian() {
  local update="$1"
  local ms_list="/etc/apt/sources.list.d/microsoft-prod.list"

  if [[ ! -f "$ms_list" ]]; then
    local id="" version_id=""
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    version_id="${VERSION_ID:-}"
    local distro=""
    case "$id" in
      debian) distro="debian" ;;
      ubuntu) distro="ubuntu" ;;
      *)
        if [[ "${ID_LIKE:-}" == *ubuntu* ]]; then distro="ubuntu"
        elif [[ "${ID_LIKE:-}" == *debian* ]]; then distro="debian"
        fi
        ;;
    esac
    if [[ -z "$distro" || -z "$version_id" ]]; then
      info "pwsh: could not detect Debian/Ubuntu variant (ID=$id VERSION_ID=$version_id); skipping"
      return
    fi
    local deb_url="https://packages.microsoft.com/config/${distro}/${version_id}/packages-microsoft-prod.deb"
    local tmp
    tmp="$(mktemp -t packages-microsoft-prod.XXXXXX.deb)" || fail "Failed to create temp file"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN
    http_get_retry "$deb_url" "$tmp" \
      || fail "Failed to download packages-microsoft-prod.deb from $deb_url"
    sudo dpkg -i "$tmp" || fail "Failed to install packages-microsoft-prod.deb"
    sudo apt update -y || fail "Failed to apt update after adding Microsoft repo"
  fi

  sudo apt install -y powershell || fail "Failed to install powershell via apt"
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all `setup_pwsh` tests pass, no regressions.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Implement setup_pwsh Debian/Ubuntu branch"
```

---

## Task 4: `setup_pwsh` — Arch branch

**Files:**
- Modify: `scripts/packages.sh`
- Modify: `tests/bash/test_packages.sh`

- [ ] **Step 1: Write failing test**

Append after the existing `setup_pwsh` tests:

```bash
test_setup_pwsh_dry_run_arch() {
  detect_platform() { echo "arch"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)

  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished pwsh"
}
```

- [ ] **Step 2: Run test to verify it passes against skeleton**

The test uses `DRY=true` so it doesn't reach `_setup_pwsh_arch`. It should already pass.

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: `test_setup_pwsh_dry_run_arch` passes.

- [ ] **Step 3: Replace the `_setup_pwsh_arch` placeholder in `scripts/packages.sh`**

Find:

```bash
_setup_pwsh_arch() { :; }
```

Replace with:

```bash
# Install or update pwsh on Arch via yay (AUR: powershell-bin).
# $1 = "true" for --update mode (no --needed, so yay re-fetches).
_setup_pwsh_arch() {
  local update="$1"
  command -v yay >/dev/null 2>&1 || fail "yay required for pwsh on Arch (run setup_yay first)"
  if [[ "$update" == "true" ]]; then
    yay -S --noconfirm powershell-bin || fail "Failed to update powershell-bin via yay"
  else
    yay -S --needed --noconfirm powershell-bin || fail "Failed to install powershell-bin via yay"
  fi
}
```

- [ ] **Step 4: Run tests**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Implement setup_pwsh Arch branch via yay"
```

---

## Task 5: Wire `setup_pwsh` and `setup_yay` into install/update flows

**Files:**
- Modify: `scripts/packages.sh`

- [ ] **Step 1: Extend `install_debian`**

Find in `scripts/packages.sh`:

```bash
function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_lazygit
    setup_neovim
    setup_zoxide

    setup_fdfind
  fi
  success "Finished install for Debian"
}
```

Replace the inner block to add `setup_pwsh` after `setup_fdfind`:

```bash
function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_lazygit
    setup_neovim
    setup_zoxide

    setup_fdfind
    setup_pwsh
  fi
  success "Finished install for Debian"
}
```

- [ ] **Step 2: Extend `install_arch`**

Find:

```bash
function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}" \
      || fail "Failed to install Arch packages"

    setup_neovim
    setup_fdfind
  fi
  success "Finished install for Arch Linux"
}
```

Replace the inner block to add `setup_yay` and `setup_pwsh`:

```bash
function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}" \
      || fail "Failed to install Arch packages"

    setup_neovim
    setup_fdfind
    setup_yay
    setup_pwsh
  fi
  success "Finished install for Arch Linux"
}
```

- [ ] **Step 3: Extend `install_mac` — add cask**

Find:

```bash
MAC_BREW_CASKS=(ghostty)
```

Replace:

```bash
MAC_BREW_CASKS=(ghostty powershell)
```

- [ ] **Step 4: Extend `update_debian`**

Find:

```bash
function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_lazygit --update
    setup_zoxide --update
  fi
  success "Finished update for Debian"
}
```

Replace the inner block to add `setup_pwsh --update`:

```bash
function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_lazygit --update
    setup_zoxide --update
    setup_pwsh --update
  fi
  success "Finished update for Debian"
}
```

- [ ] **Step 5: Extend `update_arch`**

Find:

```bash
function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
  fi
  success "Finished update for Arch Linux"
}
```

Replace the inner block to add `setup_pwsh --update`:

```bash
function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
    setup_pwsh --update
  fi
  success "Finished update for Arch Linux"
}
```

- [ ] **Step 6: Run the full packages test suite**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: all tests pass. The existing `install_*` / `update_*` tests (if any) still pass because the new calls are behind `DRY=false`, which test mode avoids.

- [ ] **Step 7: Commit**

```bash
git add scripts/packages.sh
git commit -m "Wire setup_pwsh and setup_yay into install/update flows"
```

---

## Task 6: Add `pwsh` to `verify.sh` REQUIRED_TOOLS

**Files:**
- Modify: `scripts/verify.sh`

- [ ] **Step 1: Update `REQUIRED_TOOLS`**

Find in `scripts/verify.sh`:

```bash
REQUIRED_TOOLS=(git zsh vim nvim tmux fzf fd rg lazygit zoxide)
```

Replace:

```bash
REQUIRED_TOOLS=(git zsh vim nvim tmux fzf fd rg lazygit zoxide pwsh)
```

- [ ] **Step 2: Run verify tests**

Run: `bash tests/bash/runner.sh --no-docker test_verify.sh`
Expected: all tests pass. `test_verify.sh` does not pin `REQUIRED_TOOLS` contents, so adding `pwsh` is transparent to it.

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: 188 tests pass (180 pre-existing + 8 new).

- [ ] **Step 4: Commit**

```bash
git add scripts/verify.sh
git commit -m "Add pwsh to verify REQUIRED_TOOLS"
```

---

## Task 7: Final verification

- [ ] **Step 1: Shellcheck**

Run: `shellcheck scripts/packages.sh scripts/verify.sh`
Expected: no new warnings introduced. The existing `# shellcheck disable=...` directives are preserved on copy.

- [ ] **Step 2: Dry-run the full dotfile flow**

Run: `./dotfile -d packages`
Expected: dry-run output includes "Installing pwsh..." (on Debian/Arch) or no pwsh-specific output (on Mac — cask is silent in the `MAC_BREW_CASKS` echo).

- [ ] **Step 3: Run the full test suite one more time**

Run: `bash tests/bash/runner.sh`
Expected: 188 tests pass (uses Docker; same result).

- [ ] **Step 4: No commit needed** — this task is verification only. If any step fails, fix and commit as a follow-up.

---

## Self-review summary

- **Spec coverage:**
  - Debian/Ubuntu branch → Task 3 ✓
  - Arch yay bootstrap → Task 1 ✓
  - Arch pwsh via yay → Task 4 ✓
  - Mac cask + no-op `setup_pwsh` → Task 2 (skeleton) + Task 5 (cask) ✓
  - `--update` support → Tasks 2/3/4/5 ✓
  - `verify.sh` `pwsh` entry → Task 6 ✓
  - Tests for all functions → Tasks 1/2/3/4 ✓
- **Placeholder scan:** no TBD / TODO / "handle edge cases" / unspecified code blocks.
- **Type consistency:** `setup_yay`, `setup_pwsh`, `_setup_pwsh_debian`, `_setup_pwsh_arch`, `REQUIRED_TOOLS`, `MAC_BREW_CASKS` names match across tasks.
