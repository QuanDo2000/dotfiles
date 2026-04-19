# `tests/bash/test_obsidian.sh` design

## Background

`scripts/obsidian.sh` (the `dotfile obsidian` subcommand setup) has no test
coverage. Every other module under `scripts/` has a sibling `test_<module>.sh`.
The audit on 2026-04-18 flagged this as a medium-severity gap.

The script is Linux-only (relies on systemd user units), wraps three external
tools (`npm`, `obsidian-headless`'s `ob`, `systemctl`), and includes
interactive prompts. None of those pieces should run for real in tests.

## Goal

Add `tests/bash/test_obsidian.sh` with per-helper happy + failure-path
coverage (~13 tests). Match the depth of `test_extras.sh`,
`test_packages.sh`, and `test_languages.sh`. Mock all external commands via
the existing `FAKE_BIN` PATH-shadowing pattern.

## Out of scope

- End-to-end coverage of `setup_obsidian`. The helpers it composes are each
  independently tested; an orchestrator test would mostly duplicate them.
- Real `obsidian-headless` or systemd execution. Everything is mocked.
- New CI lanes. The bash test runner already discovers `test_*.sh` files.

## Setup boilerplate

```bash
#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh platform.sh obsidian.sh
  mock_uname Linux                         # is_linux → true
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

mock_cmd() {                               # copied from test_extras.sh
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
}
```

## Test list

### `_obsidian_check_prereqs` (4 tests)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_check_prereqs_fails_on_non_linux` | `mock_uname Darwin` | helper exits non-zero, output mentions "only supported on Linux" |
| `test_check_prereqs_fails_when_npm_missing` | no npm mock | helper exits non-zero, output mentions "npm not found" |
| `test_check_prereqs_fails_when_systemctl_missing` | mock npm only | helper exits non-zero, output mentions "systemctl not found" |
| `test_check_prereqs_succeeds_with_all_tools` | mock npm, systemctl (exit 0 for `show-environment`) | helper exits 0 |

Failure-path tests use a subshell so `fail`'s `exit 1` doesn't kill the
runner: `(_obsidian_check_prereqs) 2>&1; exit_code=$?`.

### `_obsidian_install_cli` (3 tests)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_install_cli_dry_run_does_not_call_npm` | `DRY=true`; canary npm mock that exits 99 | helper exits 0, output contains "Would run", canary not tripped |
| `test_install_cli_already_installed_short_circuits` | mock `ob` (any body); canary npm mock | helper exits 0, output contains "already installed" |
| `test_install_cli_invokes_npm_when_missing` | mock npm to exit 0; no `ob` mock | helper exits 0, output contains "Finished installing" |

### `_obsidian_login` (2 tests)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_login_skips_when_already_logged_in` | mock `ob` so `sync-list-remote` exits 0; canary on `ob login` | helper exits 0, output contains "Already logged in" |
| `test_login_dry_run_does_not_call_ob` | `DRY=true`; canary `ob` mock | helper exits 0, output contains "Would run", canary not tripped |

### `_obsidian_pick_vault` (1 test)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_pick_vault_dry_run_returns_example` | `DRY=true` | stdout equals `example-vault` |

### `_obsidian_setup_vault` (2 tests)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_setup_vault_dry_run_does_not_mkdir_or_call_ob` | `DRY=true`; canary `ob` mock | helper exits 0, vault path NOT created, canary not tripped |
| `test_setup_vault_skips_when_already_configured` | create vault dir; mock `ob sync-status` to exit 0; canary on `ob sync-setup` | helper exits 0, output contains "already configured" |

### `_obsidian_install_service` (3 tests)

| Test | Setup | Assertion |
|------|-------|-----------|
| `test_install_service_dry_run_writes_nothing` | `DRY=true`; mock `ob` (so `command -v ob` finds it); canary systemctl | service file does NOT exist, canary not tripped |
| `test_install_service_writes_unit_and_enables` | mock `ob`, mock systemctl to exit 0 | service file exists, contains expected `ExecStart=…/ob sync --path … --continuous` |
| `test_install_service_force_overwrites` | pre-create service file with sentinel content; `FORCE=true`; mock ob and systemctl | service file content no longer contains the sentinel |

For the FORCE off-path: `FORCE=false` (default) + pre-existing file → file
content is unchanged. Covered as part of the same test by asserting both
behaviors? No — keep it as a fourth test only if `FORCE=false` is not already
implicit in test 2 (it isn't — test 2 has no pre-existing file). Add as
`test_install_service_skips_when_file_exists_without_force`.

That brings the section to **4 tests**, total **15** (still in the ~13
ballpark approved by the user).

## Mocking patterns

- **`command -v <name>` simulation:** `command -v` consults `PATH`. Since
  `FAKE_BIN` is at the front, present == file in `FAKE_BIN`, missing == no
  file. No special handling needed.
- **`ob` with subcommand-dependent exit codes:**
  ```bash
  mock_cmd ob 'case "$1" in
    sync-list-remote) exit 0 ;;
    sync-status) exit 0 ;;
    *) exit 0 ;;
  esac'
  ```
  Override per-test as needed (e.g., `sync-list-remote` exits 1 to force
  the login path).
- **Canary mocks:** for assertions that a command must NOT be called, mock it
  with `exit 99` and treat any exit code 99 as a regression.
- **`fail` exits the shell:** wrap helpers expected to fail in `(...)` and
  capture `$?`.
- **systemd file path:** the helper writes to
  `$HOME/.config/systemd/user/obsidian-sync.service`. Tests use
  `assert_file_exists` and `assert_contains` against `cat` of that file.

## Acceptance criteria

- `bash tests/bash/runner.sh --no-docker test_obsidian.sh` reports `15
  passed, 0 failed`.
- Full suite (`bash tests/bash/runner.sh --no-docker`) still reports the
  same pass count as before plus 15.
- No real `npm`, `ob`, `systemctl`, or `git` invocations during the run
  (canary mocks would catch this).
- Tests work without `npm`, `obsidian-headless`, or `systemd` installed on
  the host.
