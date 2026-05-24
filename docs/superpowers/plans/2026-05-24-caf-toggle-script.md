# caf Toggle Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Mac-only `caf` command at `config/mac/bin/caf` that toggles `caffeinate -d -i` (display + idle sleep prevention) on/off via a PID file at `/tmp/caf.pid`.

**Architecture:** A single bash script. The existing `setup_symlinks_folder` in `scripts/symlinks.sh` already symlinks `<layer>/bin/*` into `~/.local/bin/` and the Mac layer is only applied when `is_mac` returns true, so no wiring changes are needed. Test coverage is one new function in `tests/bash/test_symlinks.sh` that, under `mock_uname Darwin`, runs the full `setup_symlinks` against a temp `DOTFILES_DIR` populated with a copy of the real `caf` script and asserts `~/.local/bin/caf` becomes a symlink to it.

**Tech Stack:** bash, macOS `caffeinate`, `kill -0` for liveness checks, `nohup` for backgrounding.

**Spec:** [docs/superpowers/specs/2026-05-24-caf-toggle-script-design.md](../specs/2026-05-24-caf-toggle-script-design.md)

---

### Task 1: Add the `caf` script and its presence test

**Files:**
- Create: `config/mac/bin/caf`
- Modify: `tests/bash/test_symlinks.sh` (add one test function at the end of the file)

- [ ] **Step 1: Write the failing test**

Open `tests/bash/test_symlinks.sh` and append at the end of the file (after the last existing `test_*` function):

```bash
test_setup_symlinks_links_caf_on_mac() {
  local overwrite_all=false backup_all=false skip_all=false
  mock_uname Darwin

  mkdir -p "$DOTFILES_DIR/config/mac/bin"
  cp "$REPO_DIR/config/mac/bin/caf" "$DOTFILES_DIR/config/mac/bin/caf"
  chmod +x "$DOTFILES_DIR/config/mac/bin/caf"

  setup_symlinks

  assert_symlink "$HOME/.local/bin/caf" "$DOTFILES_DIR/config/mac/bin/caf"
}
```

Notes for the engineer:
- `REPO_DIR` is exported by `tests/bash/helpers.sh:4` and points at the real dotfiles repo root. `DOTFILES_DIR` is the temp dir from `init_test_env` (`tests/bash/helpers.sh:27`).
- `mock_uname Darwin` makes `is_mac` return true inside the test (`tests/bash/helpers.sh:66`). It is auto-cleared by `cleanup_test_env` in `teardown`.
- The test populates only `config/mac/bin/`; the other branches inside `setup_symlinks` (shared, unix, ssh, claude, opencode, dotfile entry point) are all guarded by `[[ -f ... ]]` / `[[ -d ... ]]` checks (`scripts/symlinks.sh:83, 137, 148, 165, 174`), so they no-op cleanly when those paths are absent.
- The `cp` from the real `config/mac/bin/caf` will fail the test with a clear error if the file doesn't exist yet — which is exactly the red state we want before Step 3.

- [ ] **Step 2: Run the test to verify it fails**

Run from the repo root:

```bash
bash tests/bash/runner.sh --no-docker test_symlinks.sh
```

Expected: `test_setup_symlinks_links_caf_on_mac` fails — the `cp` step errors with "No such file or directory" because `config/mac/bin/caf` does not exist yet, and the subsequent `assert_symlink` also fails. All other tests still pass.

- [ ] **Step 3: Create the `caf` script**

Create `config/mac/bin/caf` with exactly this content:

```bash
#!/bin/bash
set -eu

PID_FILE=/tmp/caf.pid

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    rm -f "$PID_FILE"
    echo "caf: OFF"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

nohup caffeinate -d -i >/dev/null 2>&1 &
echo "$!" > "$PID_FILE"
echo "caf: ON (pid $!)"
```

- [ ] **Step 4: Mark the script executable**

Run from the repo root:

```bash
chmod +x config/mac/bin/caf
```

- [ ] **Step 5: Syntax-check the script**

Run from the repo root:

```bash
bash -n config/mac/bin/caf
```

Expected: no output, exit code 0.

- [ ] **Step 6: Re-run the test suite to verify it passes**

Run from the repo root:

```bash
bash tests/bash/runner.sh --no-docker test_symlinks.sh
```

Expected: all tests pass, including `test_caf_script_present_and_executable`.

- [ ] **Step 7: Run the full bash test suite to confirm no regressions**

Run from the repo root:

```bash
bash tests/bash/runner.sh --no-docker
```

Expected: every test file passes. (No regressions from the change above.)

- [ ] **Step 8: Commit**

Run from the repo root:

```bash
git add config/mac/bin/caf tests/bash/test_symlinks.sh
git commit -m "Add caf toggle script for macOS

Toggles caffeinate -d -i (display + idle sleep prevention) on/off via
a PID file at /tmp/caf.pid. Symlinks into ~/.local/bin/caf on Mac via
the existing setup_symlinks_folder bin/ pattern."
```

---

## Manual verification (Mac-only, not part of automated tests)

The toggle behavior cannot be exercised in this repo's Linux test environment because `caffeinate` is macOS-only. On a Mac after running `dotfile symlinks`, verify by hand:

1. `which caf` → `~/.local/bin/caf`.
2. `caf` → prints `caf: ON (pid <N>)`, `pgrep -lf "caffeinate -d -i"` shows the process, `/tmp/caf.pid` contains that PID.
3. `caf` again → prints `caf: OFF`, `pgrep -lf "caffeinate -d -i"` shows no match, `/tmp/caf.pid` is gone.
4. Stale-PID handling: `echo 99999 > /tmp/caf.pid` (a PID that almost certainly doesn't exist), then `caf` → should print `caf: ON (pid <N>)` (treating the stale file as off) and overwrite the file with a real PID.
