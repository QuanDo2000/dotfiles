# AI tools install (Claude Code, OpenCode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `setup_claude_code` and `setup_opencode` to `scripts/packages.sh` so `dotfile packages` installs both binaries and `dotfile update` refreshes them on Debian, Arch, and macOS.

**Architecture:** Two new platform-agnostic functions in `scripts/packages.sh`, modelled after `setup_neovim`. Each one short-circuits when its binary is already on PATH; install path runs the vendor's official `curl … | bash` script; update path delegates to the tool's built-in self-updater (`claude update`, `opencode upgrade`). Wired into the existing `install_*` and `update_*` per-platform functions.

**Tech Stack:** Bash 4+, the repo's existing test harness (`tests/bash/runner.sh`, `tests/bash/helpers.sh`).

**Spec:** `docs/superpowers/specs/2026-05-23-ai-tools-install-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/packages.sh` | Modify | Add `setup_claude_code` and `setup_opencode` after `setup_brew_linux`. Wire into `install_debian`, `install_arch`, `install_mac`, `update_debian`, `update_arch`, `update_mac`. |
| `tests/bash/test_packages.sh` | Modify | Append tests for both new functions (dry-run, already-installed, update-dry-run, update-does-not-skip). |

No new files. No changes to `verify.sh`, `symlinks.sh`, or anything Windows-side.

---

## Task 1: `setup_claude_code` function

**Files:**
- Modify: `scripts/packages.sh` (add new function after `setup_brew_linux`, before the `DEBIAN_PACKAGES=(` declaration)
- Test: `tests/bash/test_packages.sh` (append new test block)

- [ ] **Step 1: Write the four failing tests**

Append to the end of `tests/bash/test_packages.sh`:

```bash
# ---------------------------------------------------------------------------
# setup_claude_code
# ---------------------------------------------------------------------------

test_setup_claude_code_dry_run() {
  DRY=true
  local output
  output=$(setup_claude_code 2>&1)

  assert_contains "$output" "Claude Code"
  assert_contains "$output" "Finished Claude Code"
}

test_setup_claude_code_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_claude_code 2>&1)

  assert_contains "$output" "Already installed Claude Code"
}

test_setup_claude_code_update_dry_run() {
  DRY=true
  local output
  output=$(setup_claude_code --update 2>&1)

  assert_contains "$output" "Claude Code"
  assert_contains "$output" "Finished Claude Code"
}

test_setup_claude_code_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_claude_code --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: Four failures for `test_setup_claude_code_*` — all reporting `setup_claude_code: command not found` (or similar; the function does not yet exist).

- [ ] **Step 3: Add `setup_claude_code` to `scripts/packages.sh`**

Insert this function in `scripts/packages.sh` after `setup_brew_linux` ends (i.e. after the closing `}` of `setup_brew_linux`) and before the `DEBIAN_PACKAGES=(` declaration:

```bash
# Install or update Claude Code via the official install script. Self-updates
# via `claude update`. Idempotent: no-op if `claude` is on PATH (unless
# --update is passed). Usage: setup_claude_code [--update]
function setup_claude_code {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} Claude Code..."
  if [[ "$DRY" == "false" ]]; then
    if command -v claude >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        claude update || fail "Failed to update Claude Code"
      else
        info "Already installed Claude Code"
      fi
    else
      curl -fsSL https://claude.ai/install.sh | bash \
        || fail "Failed to install Claude Code"
    fi
  fi
  success "Finished Claude Code"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: All `test_setup_claude_code_*` tests pass, and no previously-passing test regresses.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Add setup_claude_code to packages.sh"
```

---

## Task 2: `setup_opencode` function

**Files:**
- Modify: `scripts/packages.sh` (add new function immediately after `setup_claude_code`)
- Test: `tests/bash/test_packages.sh` (append new test block)

- [ ] **Step 1: Write the four failing tests**

Append to the end of `tests/bash/test_packages.sh`:

```bash
# ---------------------------------------------------------------------------
# setup_opencode
# ---------------------------------------------------------------------------

test_setup_opencode_dry_run() {
  DRY=true
  local output
  output=$(setup_opencode 2>&1)

  assert_contains "$output" "OpenCode"
  assert_contains "$output" "Finished OpenCode"
}

test_setup_opencode_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/opencode"
  chmod +x "$HOME/.local/bin/opencode"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_opencode 2>&1)

  assert_contains "$output" "Already installed OpenCode"
}

test_setup_opencode_update_dry_run() {
  DRY=true
  local output
  output=$(setup_opencode --update 2>&1)

  assert_contains "$output" "OpenCode"
  assert_contains "$output" "Finished OpenCode"
}

test_setup_opencode_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/opencode"
  chmod +x "$HOME/.local/bin/opencode"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_opencode --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: Four failures for `test_setup_opencode_*` — function not yet defined.

- [ ] **Step 3: Add `setup_opencode` to `scripts/packages.sh`**

Insert this function in `scripts/packages.sh` immediately after `setup_claude_code` (i.e. after its closing `}`):

```bash
# Install or update OpenCode via the official install script. Self-updates
# via `opencode upgrade`. Idempotent: no-op if `opencode` is on PATH (unless
# --update is passed). Usage: setup_opencode [--update]
function setup_opencode {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "${update:+Updating}${update:- Installing} OpenCode..."
  if [[ "$DRY" == "false" ]]; then
    if command -v opencode >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        opencode upgrade || fail "Failed to update OpenCode"
      else
        info "Already installed OpenCode"
      fi
    else
      curl -fsSL https://opencode.ai/install | bash \
        || fail "Failed to install OpenCode"
    fi
  fi
  success "Finished OpenCode"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: All `test_setup_opencode_*` tests pass. All previously-passing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -m "Add setup_opencode to packages.sh"
```

---

## Task 3: Wire both functions into `install_*`

**Files:**
- Modify: `scripts/packages.sh` (three edits: `install_debian`, `install_arch`, `install_mac`)

No new tests — the existing test suite covers each `setup_*` function in isolation, and there are no per-platform `install_*` test cases. The wiring is a small, visually-obvious edit per function.

- [ ] **Step 1: Add calls to `install_debian`**

In `scripts/packages.sh`, locate `install_debian` (currently ends with `brew install "${DEBIAN_BREW_PACKAGES[@]}" \ || fail ...`). Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after the `brew install` line:

```bash
    setup_claude_code
    setup_opencode
```

The full block should read:

```bash
function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_neovim

    setup_fdfind
    setup_pwsh
    setup_brew_linux
    brew install "${DEBIAN_BREW_PACKAGES[@]}" \
      || fail "Failed to install Debian brew packages"
    setup_claude_code
    setup_opencode
  fi
  success "Finished install for Debian"
}
```

- [ ] **Step 2: Add calls to `install_arch`**

In `scripts/packages.sh`, locate `install_arch`. Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after the existing `setup_pwsh` call:

```bash
    setup_claude_code
    setup_opencode
```

The full block should read:

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
    setup_claude_code
    setup_opencode
  fi
  success "Finished install for Arch Linux"
}
```

- [ ] **Step 3: Add calls to `install_mac`**

In `scripts/packages.sh`, locate `install_mac`. Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after the `brew install --cask` line:

```bash
    setup_claude_code
    setup_opencode
```

The full block should read:

```bash
function install_mac {
  info "Installing packages and programs for Mac..."
  if [[ "$DRY" == "false" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install "${MAC_BREW_PACKAGES[@]}"
    brew install --cask "${MAC_BREW_CASKS[@]}"
    setup_claude_code
    setup_opencode
  fi
  success "Finished install for Mac"
}
```

- [ ] **Step 4: Re-run the test suite to confirm nothing regressed**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: All tests pass (including the `setup_claude_code_*` and `setup_opencode_*` tests from Tasks 1–2). The `install_*` edits are not exercised directly by tests, but the suite confirms the file still parses and existing functions still behave.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh
git commit -m "Wire setup_claude_code and setup_opencode into install_*"
```

---

## Task 4: Wire both functions into `update_*`

**Files:**
- Modify: `scripts/packages.sh` (three edits: `update_debian`, `update_arch`, `update_mac`)

- [ ] **Step 1: Add update calls to `update_debian`**

In `scripts/packages.sh`, locate `update_debian`. Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after `setup_brew_linux --update`:

```bash
    setup_claude_code --update
    setup_opencode --update
```

The full block should read:

```bash
function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_neovim --update
    setup_pwsh --update
    setup_brew_linux --update
    setup_claude_code --update
    setup_opencode --update
  fi
  success "Finished update for Debian"
}
```

- [ ] **Step 2: Add update calls to `update_arch`**

In `scripts/packages.sh`, locate `update_arch`. Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after `setup_pwsh --update`:

```bash
    setup_claude_code --update
    setup_opencode --update
```

The full block should read:

```bash
function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    setup_neovim --update
    setup_pwsh --update
    setup_claude_code --update
    setup_opencode --update
  fi
  success "Finished update for Arch Linux"
}
```

- [ ] **Step 3: Add update calls to `update_mac`**

In `scripts/packages.sh`, locate `update_mac`. Add two lines inside the `if [[ "$DRY" == "false" ]]; then` block, immediately after `brew upgrade`:

```bash
    setup_claude_code --update
    setup_opencode --update
```

The full block should read:

```bash
function update_mac {
  info "Updating packages for Mac..."
  if [[ "$DRY" == "false" ]]; then
    brew update || fail "Failed to update brew"
    brew upgrade || fail "Failed to upgrade brew packages"
    setup_claude_code --update
    setup_opencode --update
  fi
  success "Finished update for Mac"
}
```

- [ ] **Step 4: Re-run the test suite**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`

Expected: All tests pass.

- [ ] **Step 5: Run the full bash test suite as a final regression check**

Run: `bash tests/bash/runner.sh --no-docker`

Expected: All tests across all files pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/packages.sh
git commit -m "Wire setup_claude_code and setup_opencode into update_*"
```

---

## Self-review notes

**Spec coverage check:**
- "Two new functions in `scripts/packages.sh`" → Tasks 1 & 2.
- "Wire into install_debian/arch/mac" → Task 3.
- "Wire into update_debian/arch/mac with `--update`" → Task 4.
- "Tests in `test_packages.sh`: dry-run, already-installed short-circuit, --update mode" → covered in Tasks 1 & 2.
- "No changes to `verify.sh`" → respected.

**Placeholder scan:** no TBDs, no "similar to Task N", every code block is complete.

**Type/identifier consistency:** function names match across tasks (`setup_claude_code`, `setup_opencode`), binary names match (`claude`, `opencode`), update commands match (`claude update`, `opencode upgrade`).

**One thing to verify at implementation time:** the install URL `https://claude.ai/install.sh` and the update command `claude update`. If either has moved/renamed by the time this is executed, swap to the current vendor-documented equivalent and adjust the test expectations only if the user-visible log strings change.
