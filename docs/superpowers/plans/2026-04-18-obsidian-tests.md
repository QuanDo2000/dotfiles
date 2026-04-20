# `tests/bash/test_obsidian.sh` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `tests/bash/test_obsidian.sh` covering each helper in `scripts/obsidian.sh` (per-helper happy + failure paths, ~15 tests).

**Architecture:** Single new test file. Mocks `npm`, `ob`, `systemctl` via the `FAKE_BIN` PATH-shadowing pattern from `test_extras.sh`. Mocks `uname` via the existing `mock_uname` helper. Failure-path tests run helpers in subshells to swallow `fail`'s `exit 1`.

**Tech Stack:** Bash test runner (`tests/bash/runner.sh`). Helpers in `tests/bash/helpers.sh`. Source under test: `scripts/obsidian.sh` (Linux-only; relies on systemd user units).

**Related design spec:** `docs/superpowers/specs/2026-04-18-obsidian-tests-design.md`

**Note on TDD:** This plan adds characterization tests to existing code. Tests should pass on first write. If any fail, that surfaces a genuine bug in `scripts/obsidian.sh` — investigate before forcing them green.

---

## File map

- **Create:** `tests/bash/test_obsidian.sh` (single new file, grows across tasks 1–6).
- **No production code changes** in `scripts/obsidian.sh` are expected. If a test reveals a bug, stop and surface it; do not silently change `obsidian.sh` to make tests pass.

---

## Task 1: Create test file skeleton + `_obsidian_check_prereqs` tests

**Files:**
- Create: `tests/bash/test_obsidian.sh`

- [ ] **Step 1: Write the test file with setup boilerplate and the 4 prereq tests**

Create `tests/bash/test_obsidian.sh` with this exact content:

```bash
#!/bin/bash
# Tests for scripts/obsidian.sh (Obsidian headless sync setup).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh platform.sh obsidian.sh
  mock_uname Linux
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

# Helper: install a fake executable in FAKE_BIN that runs $body.
mock_cmd() {
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
}

# ---------------------------------------------------------------------------
# _obsidian_check_prereqs
# ---------------------------------------------------------------------------

test_check_prereqs_fails_on_non_linux() {
  mock_uname Darwin

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail on non-Linux" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "only supported on Linux"
}

test_check_prereqs_fails_when_npm_missing() {
  # No npm mock installed → command -v npm returns non-zero.
  mock_cmd systemctl 'exit 0'

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail when npm missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "npm not found"
}

test_check_prereqs_fails_when_systemctl_missing() {
  mock_cmd npm 'exit 0'
  # No systemctl mock.

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail when systemctl missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "systemctl not found"
}

test_check_prereqs_succeeds_with_all_tools() {
  mock_cmd npm 'exit 0'
  mock_cmd systemctl 'exit 0'  # any --user show-environment call returns 0

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should succeed with all tools ($output)" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 4 passed, 0 failed, 4 total ===`

If any fail, read the failure message — it indicates either a bug in `obsidian.sh` (surface it) or a bug in the test (fix it).

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add tests for _obsidian_check_prereqs"
```

---

## Task 2: `_obsidian_install_cli` tests

**Files:**
- Modify: `tests/bash/test_obsidian.sh` (append a new section)

- [ ] **Step 1: Append the 3 tests**

Append to `tests/bash/test_obsidian.sh`:

```bash
# ---------------------------------------------------------------------------
# _obsidian_install_cli
# ---------------------------------------------------------------------------

test_install_cli_dry_run_does_not_call_npm() {
  DRY=true
  # Canary: any npm invocation in DRY mode is a regression.
  mock_cmd npm 'echo "unexpected npm call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should not call npm in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run: npm install -g obsidian-headless"
}

test_install_cli_already_installed_short_circuits() {
  # `ob` present on PATH → command -v ob succeeds → npm should not be called.
  mock_cmd ob 'exit 0'
  mock_cmd npm 'echo "unexpected npm call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should short-circuit when ob present ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already installed"
}

test_install_cli_invokes_npm_when_missing() {
  # No `ob` mock → command -v ob fails → npm install runs.
  mock_cmd npm 'exit 0'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should succeed when npm exits 0 ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing"
}
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 7 passed, 0 failed, 7 total ===`

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add tests for _obsidian_install_cli"
```

---

## Task 3: `_obsidian_login` tests

**Files:**
- Modify: `tests/bash/test_obsidian.sh` (append)

- [ ] **Step 1: Append the 2 tests**

Append to `tests/bash/test_obsidian.sh`:

```bash
# ---------------------------------------------------------------------------
# _obsidian_login
# ---------------------------------------------------------------------------

test_login_skips_when_already_logged_in() {
  # `ob sync-list-remote` exits 0 → already logged in → `ob login` must NOT run.
  mock_cmd ob 'case "$1" in
    sync-list-remote) exit 0 ;;
    login) echo "unexpected ob login call" >&2; exit 99 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_login 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_login should succeed when already logged in ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Already logged in"
}

test_login_dry_run_does_not_call_ob() {
  DRY=true
  # Canary: any ob invocation in DRY mode is a regression.
  mock_cmd ob 'echo "unexpected ob call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_login 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_login should not call ob in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run: ob login"
}
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 9 passed, 0 failed, 9 total ===`

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add tests for _obsidian_login"
```

---

## Task 4: `_obsidian_pick_vault` test

**Files:**
- Modify: `tests/bash/test_obsidian.sh` (append)

- [ ] **Step 1: Append the test**

Append to `tests/bash/test_obsidian.sh`:

```bash
# ---------------------------------------------------------------------------
# _obsidian_pick_vault
# ---------------------------------------------------------------------------

test_pick_vault_dry_run_returns_example() {
  DRY=true

  local stdout
  stdout=$(_obsidian_pick_vault 2>/dev/null)

  assert_equals "example-vault" "$stdout"
}
```

- [ ] **Step 2: Run the new test**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 10 passed, 0 failed, 10 total ===`

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add test for _obsidian_pick_vault"
```

---

## Task 5: `_obsidian_setup_vault` tests

**Files:**
- Modify: `tests/bash/test_obsidian.sh` (append)

- [ ] **Step 1: Append the 2 tests**

Append to `tests/bash/test_obsidian.sh`:

```bash
# ---------------------------------------------------------------------------
# _obsidian_setup_vault
# ---------------------------------------------------------------------------

test_setup_vault_dry_run_does_not_mkdir_or_call_ob() {
  DRY=true
  mock_cmd ob 'echo "unexpected ob call: $*" >&2; exit 99'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_setup_vault "test-vault" "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should not call ob in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  if [ -d "$vault_path" ]; then
    echo "  FAILED: _obsidian_setup_vault should not create vault dir in DRY mode" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run"
}

test_setup_vault_skips_when_already_configured() {
  local vault_path="$HOME/documents/obsidian/test-vault"
  mkdir -p "$vault_path"
  # sync-status exits 0 → already configured → sync-setup must NOT run.
  mock_cmd ob 'case "$1" in
    sync-status) exit 0 ;;
    sync-setup) echo "unexpected ob sync-setup call" >&2; exit 99 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_setup_vault "test-vault" "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should skip when configured ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already configured"
}
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 12 passed, 0 failed, 12 total ===`

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add tests for _obsidian_setup_vault"
```

---

## Task 6: `_obsidian_install_service` tests

**Files:**
- Modify: `tests/bash/test_obsidian.sh` (append)

- [ ] **Step 1: Append the 4 tests**

Append to `tests/bash/test_obsidian.sh`:

```bash
# ---------------------------------------------------------------------------
# _obsidian_install_service
# ---------------------------------------------------------------------------

test_install_service_dry_run_writes_nothing() {
  DRY=true
  # ob must be on PATH so command -v ob succeeds (the helper resolves the path).
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'echo "unexpected systemctl call: $*" >&2; exit 99'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should not call systemctl in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  if [ -f "$OBSIDIAN_SERVICE_PATH" ]; then
    echo "  FAILED: _obsidian_install_service should not write service file in DRY mode" >> "$ERROR_FILE"
  fi
}

test_install_service_writes_unit_and_enables() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should succeed ($output)" >> "$ERROR_FILE"
  fi
  assert_file_exists "$OBSIDIAN_SERVICE_PATH"

  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  assert_contains "$unit_content" "ob sync --path $vault_path --continuous"
  assert_contains "$unit_content" "WantedBy=default.target"
}

test_install_service_skips_when_file_exists_without_force() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'
  FORCE=false
  mkdir -p "$(dirname "$OBSIDIAN_SERVICE_PATH")"
  echo "SENTINEL_PRE_EXISTING_CONTENT" > "$OBSIDIAN_SERVICE_PATH"

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should succeed without overwriting ($output)" >> "$ERROR_FILE"
  fi
  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  assert_contains "$unit_content" "SENTINEL_PRE_EXISTING_CONTENT"
  assert_contains "$output" "use -f to overwrite"
}

test_install_service_force_overwrites() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'
  FORCE=true
  mkdir -p "$(dirname "$OBSIDIAN_SERVICE_PATH")"
  echo "SENTINEL_PRE_EXISTING_CONTENT" > "$OBSIDIAN_SERVICE_PATH"

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should overwrite with FORCE ($output)" >> "$ERROR_FILE"
  fi
  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  if [[ "$unit_content" == *"SENTINEL_PRE_EXISTING_CONTENT"* ]]; then
    echo "  FAILED: _obsidian_install_service with FORCE should overwrite sentinel" >> "$ERROR_FILE"
  fi
  assert_contains "$unit_content" "ob sync --path $vault_path --continuous"
}
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/bash/runner.sh --no-docker test_obsidian.sh`
Expected: `=== Results: 16 passed, 0 failed, 16 total ===`

(Spec said 15; this expanded to 16 because the FORCE off-path warranted its own test rather than being bundled into the FORCE-on test.)

- [ ] **Step 3: Commit**

```bash
git add tests/bash/test_obsidian.sh
git commit -m "Add tests for _obsidian_install_service"
```

---

## Task 7: Full-suite regression check

**Files:** none (verification only)

- [ ] **Step 1: Run the full bash suite**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: `=== Results: 247 passed, 0 failed, 247 total ===`

(Before this work the suite reported 231 passed. 231 + 16 = 247.)

- [ ] **Step 2: Run the Docker variant for sanity**

Run: `bash tests/bash/runner.sh test_obsidian.sh`
Expected: `=== Results: 16 passed, 0 failed, 16 total ===`

(The Docker run is the default mode; verifying it picks up the new file rules out path issues.)

- [ ] **Step 3: No commit**

Verification only. If anything fails, return to the appropriate task.

---

## Self-Review Notes

**1. Spec coverage:**
- `_obsidian_check_prereqs` 4 tests → Task 1 ✓
- `_obsidian_install_cli` 3 tests → Task 2 ✓
- `_obsidian_login` 2 tests → Task 3 ✓
- `_obsidian_pick_vault` 1 test → Task 4 ✓
- `_obsidian_setup_vault` 2 tests → Task 5 ✓
- `_obsidian_install_service` 4 tests (3 from spec + force-off path the spec already added) → Task 6 ✓
- Setup boilerplate (mock_cmd, FAKE_BIN, mock_uname Linux) → Task 1 ✓
- Acceptance criterion "no real npm/ob/systemctl/git invocations" → enforced by canary mocks throughout
- Acceptance criterion "tests work without npm/obsidian-headless/systemd installed" → all paths mocked; PATH manipulation isolates from host

**2. Placeholder scan:** none.

**3. Type/name consistency:**
- `_obsidian_*` function names match `scripts/obsidian.sh` (verified against the file).
- `OBSIDIAN_SERVICE_PATH` is the global from `scripts/obsidian.sh:5`. Tasks 6 use it directly — `source_scripts utils.sh platform.sh obsidian.sh` makes it available.
- Globals: `DRY`, `FORCE`, `HOME`, `TEST_TMPDIR`, `ERROR_FILE` all match `helpers.sh` and `runner.sh` exports.
- Assertions: `assert_equals`, `assert_contains`, `assert_file_exists` are defined in `runner.sh:69-88`. No `assert_dir_exists` or `assert_not_contains` is used (would have been undefined).

**4. Note on the 247 expected total** in Task 7: the current main has 231 tests passing. The 16 new tests bring the expected total to 247. If a test is added or removed elsewhere on main between now and execution, adjust accordingly.
