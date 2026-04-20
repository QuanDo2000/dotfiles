# Odin clang prerequisite — design

## Background

`install_odin` (in `scripts/languages.sh`) downloads pre-built Odin binaries
from the official GitHub releases. The Odin compiler then shells out to `clang`
at runtime to assemble and link generated C code. Without `clang` on PATH, the
install succeeds but the user's first `odin build` fails with a confusing
linker error.

The official Odin install docs (https://odin-lang.org/docs/install/) call out
this prerequisite explicitly:

- **macOS** — install Apple Command Line Tools via `xcode-select --install`
  (provides `clang`).
- **Linux** — install `clang` via the system package manager.

(The docs also list LLVM 14/17–21 as a requirement, but only for users who
build the Odin compiler from source. We install pre-built binaries, so a
runtime `clang` is sufficient.)

## Goal

Before `install_odin` proceeds, verify `clang` is available and either install
it (Linux) or fail with actionable instructions (macOS).

## Architecture

Follows the existing `ensure_*` helper pattern in `scripts/languages.sh`
(`ensure_jq`, `ensure_minisign`, `ensure_erlang`, `ensure_rebar3`). One new
helper, one new call site in `install_odin`, one new test section. No
restructuring.

### 1. New helper: `ensure_clang`

Location: `scripts/languages.sh`, immediately after `ensure_rebar3` (currently
ending around line 591).

Behavior by platform (via `detect_platform`):

- **debian** — if `command -v clang` fails, run
  `sudo apt install -y clang`. Honors `DRY=true` by logging intent and
  returning 0.
- **arch** — if `command -v clang` fails, run
  `sudo pacman -S --needed --noconfirm clang`. Honors `DRY=true`.
- **mac** — check `xcode-select -p >/dev/null 2>&1` rather than
  `command -v clang`. Rationale: macOS ships a `/usr/bin/clang` stub that
  exists on PATH even when Command Line Tools aren't installed; the stub
  errors at invoke time. `xcode-select -p` is the authoritative check for a
  usable CLT install.

  When CLT is missing:
  - **Real mode** (`DRY` unset/false) — call `fail` with the message:
    > clang not found. Run `xcode-select --install` to install Apple Command
    > Line Tools, then re-run.
  - **Dry-run mode** (`DRY=true`) — log an `info` message starting with
    `clang not found` and including the same `xcode-select --install`
    instruction, then `return 0`. This keeps the dry-run pipeline alive
    (matching how the other `_dry_run_mac_*` tests expect dry-run to log
    intent rather than abort) while still surfacing the missing prerequisite
    in the dry-run report.

- **other** — `fail "Cannot install clang on this platform"`, matching the
  closing case of every other `ensure_*` helper.

Why a dedicated helper rather than parameterizing one of the existing ones:
the macOS path differs in two ways (different presence check, different
failure mode — instruct rather than auto-install). Keeping the special case
inside its own helper preserves the simple shape of `ensure_jq`/`ensure_erlang`
and avoids leaking macOS quirks into them.

### 2. Wiring in `install_odin`

In `install_odin` (currently line 480), insert `ensure_clang` immediately
before `ensure_jq`. Placement matters: it must run **before** the `DRY=true`
early-return so dry runs surface a missing-clang condition. This mirrors how
`install_zig` runs `ensure_minisign` and `ensure_jq` before its dry-run check.

`update_odin` calls `install_odin` and so inherits the check automatically.
This is correct: a user who removes Xcode CLT after their initial Odin install
would otherwise hit the same compile-time failure on the next update cycle.

### 3. Tests

Add a new section to `tests/bash/test_languages.sh` after the
`ensure_rebar3` tests (around line 880), following the
`test_ensure_erlang_*` and `test_ensure_rebar3_*` pattern exactly. Five tests:

1. **`test_ensure_clang_already_present_noop`** — drop a fake `clang` into
   `$HOME/.local/bin`, prepend to PATH, assert no "not found" output. Mirrors
   `test_ensure_erlang_already_present_noop`.

2. **`test_ensure_clang_dry_run_arch_logs_install`** — `DRY=true`,
   mock `command -v clang` to fail, mock `detect_platform` → `arch`, assert
   output contains `clang not found`.

3. **`test_ensure_clang_dry_run_debian_logs_install`** — same shape, debian.

4. **`test_ensure_clang_mac_clt_present_noop`** — mock `xcode-select -p` to
   print a path and exit 0, mock `detect_platform` → `mac`, assert no
   failure / no "not found" output.

5. **`test_ensure_clang_dry_run_mac_missing_clt_logs_instruction`** —
   `DRY=true`, mock `xcode-select -p` to exit non-zero, mock
   `detect_platform` → `mac`, assert output contains `clang not found` and
   `xcode-select --install`. Under `DRY=true` the helper returns 0 without
   calling `fail` (per the dry-run contract above), matching the other
   `_dry_run_mac_*` tests' expectations.

A real-mode mac-missing-CLT failure path (no `DRY=true`, expect non-zero exit
and the instruction text) is intentionally **not** asserted, because the other
`ensure_*` tests likewise only exercise dry-run + already-present branches —
real-mode `fail` paths in those helpers aren't covered either, and we follow
the existing baseline rather than expanding test scope unrelated to this
change.

### 4. Existing test isolation

The current `install_odin` and `update_odin` tests stub out `ensure_jq` (and,
for some tests, `ensure_minisign`) so their setup doesn't actually try to
install dependencies. Those tests must additionally stub `ensure_clang` (a
no-op `return 0`) so the new dependency doesn't break them.

A grep of the test file shows the affected lines are around 597, 617, 651 in
the `install_odin`/`update_odin` test cases. Each needs the same one-line
stub pair added.

## Out of scope

- **Installing LLVM proper.** Only relevant for building Odin from source,
  which this dotfiles repo does not do.
- **Windows clang.** The `dotfile.ps1` Windows installer has its own Odin
  install path; this design only covers the unix `scripts/languages.sh`.
- **Pinning a clang version.** The Odin docs don't require a specific clang
  version at runtime; whatever version the system package manager ships is
  fine.
- **Verifying the LLVM that ships with brew/apt clang.** Out of scope for the
  same reason — we only need clang as a linker driver, not for source builds.

## Files touched

- `scripts/languages.sh` — add `ensure_clang` helper; add one call in
  `install_odin`.
- `tests/bash/test_languages.sh` — add five `test_ensure_clang_*` tests; add
  `ensure_clang` stubs to existing `install_odin`/`update_odin` tests.

No new files, no new subcommands, no symlink or CLI surface changes.
