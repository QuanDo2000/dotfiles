# Odin clang prerequisite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure `clang` is present before `install_odin` runs, since the Odin compiler shells out to clang at runtime to assemble/link generated C code.

**Architecture:** Add an `ensure_clang` helper to `scripts/languages.sh` following the existing `ensure_jq`/`ensure_erlang`/`ensure_rebar3` pattern, with a macOS-specific branch that uses `xcode-select -p` for presence detection (the `/usr/bin/clang` stub on macOS is not a usable compiler) and `fail`s with `xcode-select --install` instructions rather than auto-installing (an `xcode-select --install` invocation opens a blocking GUI prompt unsuitable for unattended `dotfile` runs). Wire it into `install_odin` ahead of the `DRY` early-return so dry-run reports also surface a missing-clang condition.

**Tech Stack:** Bash 3.2+ (macOS-portable), shell test harness in `tests/bash/` using `tests/bash/helpers.sh`.

**Spec:** `docs/superpowers/specs/2026-04-19-odin-clang-prerequisite-design.md`

---

## File Structure

- **Modify:** `scripts/languages.sh` — add `ensure_clang` helper after `ensure_rebar3`; add one call in `install_odin`.
- **Modify:** `tests/bash/test_languages.sh` — add five `test_ensure_clang_*` tests after the `ensure_rebar3` section; add `ensure_clang` stubs to three existing `install_odin`/`update_odin` tests.

No new files. No CLI surface changes. No symlink layer changes.

---

## Task 1: Add `ensure_clang` helper (TDD)

**Files:**
- Modify: `scripts/languages.sh` — add helper after line 591 (end of `ensure_rebar3`)
- Test: `tests/bash/test_languages.sh` — add new section after line 880 (end of `ensure_rebar3` tests, before the `# install_gleam` section header at line 882)

### Step 1: Write the failing tests

- [ ] Open `tests/bash/test_languages.sh` and insert this new section immediately after the `ensure_rebar3` test block (after line 880, before the `# ---...` separator that begins the `# install_gleam` section):

```bash
# ---------------------------------------------------------------------------
# ensure_clang
# ---------------------------------------------------------------------------

test_ensure_clang_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/clang"
  chmod +x "$HOME/.local/bin/clang"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_clang 2>&1)
  if [[ "$output" == *"clang not found"* ]]; then
    echo "  FAILED: ensure_clang should noop when clang already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_clang_dry_run_arch_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "clang" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(ensure_clang 2>&1)
  assert_contains "$output" "clang not found"
}

test_ensure_clang_dry_run_debian_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "clang" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(ensure_clang 2>&1)
  assert_contains "$output" "clang not found"
}

test_ensure_clang_mac_clt_present_noop() {
  detect_platform() { echo "mac"; }
  export -f detect_platform
  mock_cmd "xcode-select" 'echo "/Library/Developer/CommandLineTools"; exit 0'

  local output
  output=$(ensure_clang 2>&1)
  if [[ "$output" == *"clang not found"* ]]; then
    echo "  FAILED: ensure_clang should noop when CLT present on mac" >> "$ERROR_FILE"
  fi
}

test_ensure_clang_dry_run_mac_missing_clt_logs_instruction() {
  DRY=true
  detect_platform() { echo "mac"; }
  export -f detect_platform
  mock_cmd "xcode-select" 'exit 1'

  local output
  output=$(ensure_clang 2>&1)
  assert_contains "$output" "clang not found"
  assert_contains "$output" "xcode-select --install"
}
```

### Step 2: Run the tests to verify they fail

- [ ] Run only the new ensure_clang tests:

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh 2>&1 | grep -E "ensure_clang|FAIL|PASS" | head -40
```

Expected: All five `test_ensure_clang_*` tests FAIL with errors like "command not found: ensure_clang" (the function doesn't exist yet).

### Step 3: Implement `ensure_clang`

- [ ] Open `scripts/languages.sh` and insert this helper immediately after the closing `}` of `ensure_rebar3` (currently line 591), and before the comment block that begins with `# Install (or upgrade) Gleam` (currently line 593):

```bash
# Ensure clang is available. Required at runtime by Odin to assemble/link
# generated C code (see https://odin-lang.org/docs/install/).
#
# macOS uses xcode-select -p instead of `command -v clang` because the
# /usr/bin/clang stub exists on PATH even when Command Line Tools aren't
# installed (the stub errors at invoke time). On macOS we don't auto-install
# CLT — `xcode-select --install` opens a blocking GUI prompt unsuitable for
# unattended `dotfile` runs — so we fail with instructions instead.
ensure_clang() {
  local platform
  platform="$(detect_platform)"

  case "$platform" in
    mac)
      xcode-select -p >/dev/null 2>&1 && return 0
      info "clang not found. Run \`xcode-select --install\` to install Apple Command Line Tools, then re-run."
      [[ "$DRY" == "true" ]] && return 0
      fail "clang not found. Run \`xcode-select --install\` to install Apple Command Line Tools, then re-run."
      ;;
    *)
      command -v clang >/dev/null 2>&1 && return 0
      info "clang not found; installing..."
      [[ "$DRY" == "true" ]] && return 0
      case "$platform" in
        debian) sudo apt install -y clang || fail "Failed to install clang" ;;
        arch)   sudo pacman -S --needed --noconfirm clang || fail "Failed to install clang" ;;
        *)      fail "Cannot install clang on this platform" ;;
      esac
      success "Installed clang"
      ;;
  esac
}
```

### Step 4: Run the tests to verify they pass

- [ ] Run the new tests:

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh 2>&1 | grep -E "ensure_clang|FAIL" | head -40
```

Expected: All five `test_ensure_clang_*` tests appear in PASS output, and no FAIL lines reference `ensure_clang`.

- [ ] Then run the full `test_languages.sh` suite to confirm nothing else regressed:

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

Expected: Suite ends with a "PASS" / 0-failures summary. (If existing `install_odin`/`update_odin` tests fail because they actually invoke `ensure_clang` against the test env's real `command -v clang`, that's expected — Task 2 fixes those tests at the same time it adds the call site. But since the helper is not yet wired into `install_odin`, those tests should still pass at this point.)

### Step 5: Commit

- [ ] Stage and commit:

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "$(cat <<'EOF'
Add ensure_clang helper

Required by Odin at runtime to assemble/link generated C code (see
https://odin-lang.org/docs/install/). macOS uses xcode-select -p for
presence detection because the /usr/bin/clang stub exists on PATH even
without Command Line Tools, and fails with install instructions rather
than auto-running xcode-select --install (which opens a blocking GUI
prompt).

Not yet wired into install_odin — that's the next commit.
EOF
)"
```

---

## Task 2: Wire `ensure_clang` into `install_odin`

**Files:**
- Modify: `scripts/languages.sh:480-510` — add `ensure_clang` call to `install_odin`
- Modify: `tests/bash/test_languages.sh:595-657` — add `ensure_clang` stub to three existing tests so they remain isolated from the new dependency

### Step 1: Add `ensure_clang` stub to existing `install_odin`/`update_odin` tests

Without these stubs, the tests would invoke the real `ensure_clang` once Task 2 wires it into `install_odin`. On a Linux test runner without clang the helper would attempt `sudo apt install -y clang`, hanging the suite or polluting the host.

- [ ] In `tests/bash/test_languages.sh`, find `test_install_odin_dry_run` (currently around line 595) and add the stub after the existing `ensure_jq` stub block:

Replace:

```bash
test_install_odin_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
```

With:

```bash
test_install_odin_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_clang() { return 0; }
  export -f ensure_clang

  local output
  output=$(install_odin 2>&1)
```

- [ ] Same edit in `test_install_odin_already_installed_short_circuits` (currently around line 609). Replace:

```bash
  http_get_retry() { echo '{"tag_name": "dev-2026-04", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(install_odin 2>&1)
```

With:

```bash
  http_get_retry() { echo '{"tag_name": "dev-2026-04", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_clang() { return 0; }
  export -f ensure_clang

  local output
  output=$(install_odin 2>&1)
```

- [ ] Same edit in `test_update_odin_dry_run_when_ours` (currently around line 645). Replace:

```bash
  ensure_jq() { return 0; }
  export -f ensure_jq

  local output
  output=$(update_odin 2>&1)
```

With:

```bash
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_clang() { return 0; }
  export -f ensure_clang

  local output
  output=$(update_odin 2>&1)
```

(The other two `update_odin` tests — `test_update_odin_no_op_when_not_installed` and `test_update_odin_skips_foreign_install` — early-return before reaching `install_odin` and don't need a stub.)

### Step 2: Run those three tests to confirm they still pass

- [ ] Targeted run before adding the call site:

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh 2>&1 | grep -E "test_install_odin_dry_run|test_install_odin_already_installed|test_update_odin_dry_run_when_ours|FAIL"
```

Expected: All three tests pass; no FAIL lines reference them. (The stubs are inert until Task 2's call site exists, so these should be no-op edits behaviorally at this point.)

### Step 3: Add `ensure_clang` call to `install_odin`

- [ ] In `scripts/languages.sh`, find `install_odin` (currently line 480). Replace the opening lines:

```bash
install_odin() {
  info "Installing Odin..."
  ensure_jq
```

With:

```bash
install_odin() {
  info "Installing Odin..."
  ensure_clang
  ensure_jq
```

The `ensure_clang` call goes **before** `ensure_jq` and therefore before the `DRY=true` early-return at line 486, so dry-run reports surface a missing-clang condition just as `install_zig` surfaces a missing minisign.

### Step 4: Run the full `test_languages.sh` suite

- [ ] Confirm the wiring doesn't break anything:

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

Expected: Suite ends with PASS / 0 failures. Pay attention to `test_install_odin_dry_run`, `test_install_odin_already_installed_short_circuits`, and `test_update_odin_dry_run_when_ours` — these now exercise the new call site (with the stub).

### Step 5: Run the full bash test suite (Docker, matching CI)

- [ ] Run the full suite under Docker to catch any cross-file regression:

```bash
bash tests/bash/runner.sh
```

Expected: All test files pass.

### Step 6: Commit

- [ ] Stage and commit:

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "$(cat <<'EOF'
Wire ensure_clang into install_odin

Odin shells out to clang at runtime to assemble/link generated C code,
so verify clang is available before installing. Placed before the DRY
early-return so dry-run reports also surface a missing-clang condition.

update_odin inherits the check via install_odin, which is correct: a
user who removes Xcode CLT after their initial install would otherwise
hit the same compile-time failure on the next update cycle.
EOF
)"
```

---

## Self-Review Notes

Spec coverage check (against `docs/superpowers/specs/2026-04-19-odin-clang-prerequisite-design.md`):

- Section "1. New helper: ensure_clang" → Task 1, Step 3.
- Section "2. Wiring in install_odin" → Task 2, Step 3.
- Section "3. Tests" — five tests → Task 1, Step 1 (all five present, names match the spec including the renamed `test_ensure_clang_dry_run_mac_missing_clt_logs_instruction`).
- Section "4. Existing test isolation" → Task 2, Step 1 (three call sites: `test_install_odin_dry_run`, `test_install_odin_already_installed_short_circuits`, `test_update_odin_dry_run_when_ours`).

Type/name consistency: helper name `ensure_clang` used identically across `scripts/languages.sh` and all six test references. The fail/info message string is duplicated (real-mode `fail` and dry-run `info`) but kept identical so the dry-run test's `xcode-select --install` substring assertion matches the real-mode message a user would see.

No placeholders, no "TBD", no "similar to Task N" — every step has the literal code or command.
