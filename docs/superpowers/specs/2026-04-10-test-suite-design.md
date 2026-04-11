# Test Suite Design for Dotfiles Scripts

## Overview

A pure-bash test suite for the dotfiles installer scripts, using Docker for filesystem isolation. No external test frameworks or build tools — just `./tests/runner.sh`.

## Goals

- Catch regressions when editing scripts (utils, symlinks, CLI parsing, verify)
- Run in an isolated Docker container so tests never touch the host filesystem
- Zero external dependencies beyond Docker and bash

## Structure

```
tests/
  runner.sh          # Entry point + test framework + Docker orchestration
  test_utils.sh      # Tests for scripts/utils.sh
  test_symlinks.sh   # Tests for scripts/symlinks.sh
  test_cli.sh        # Tests for shared/bin/dotfile CLI parsing & dispatch
  test_verify.sh     # Tests for scripts/verify.sh
```

No Makefile, no separate Dockerfile.

## Runner (`tests/runner.sh`)

### Docker Orchestration

When invoked on the host, `runner.sh`:

1. Detects it is NOT inside Docker (no `/.dockerenv`)
2. Builds a Docker image from an inline heredoc Dockerfile (ubuntu-based, installs bash + coreutils + git + diffutils)
3. Runs a container that mounts the repo and executes `runner.sh` inside it
4. Exits with the container's exit code

When invoked inside the container, it runs tests directly.

A `--no-docker` flag skips Docker and runs tests directly on the host (useful for debugging).

### Test Framework

~50-80 lines of pure bash. Responsibilities:

- **Discovery**: sources each `tests/test_*.sh` file, finds all `test_*` functions via `declare -F`
- **Isolation**: runs each test function in a subshell
- **Setup/teardown**: calls `setup` before and `teardown` after each test if defined in the test file
- **Assertions**:
  - `assert_equals <expected> <actual>` — string equality
  - `assert_contains <haystack> <needle>` — substring match
  - `assert_file_exists <path>` — file exists
  - `assert_symlink <path> <target>` — symlink points to expected target
  - `assert_exit_code <expected> <command...>` — command exits with expected code
- **Reporting**: prints pass/fail per test, summary at end (total, passed, failed), exits non-zero if any failed

## Docker Image

Based on `ubuntu:latest`. Installs only:
- bash, coreutils, git, diffutils

Does NOT install zsh, tmux, neovim, etc. — tests verify behavior with and without tools present.

## Test Coverage

### test_utils.sh

| Test | What it verifies |
|------|-----------------|
| `test_info_output` | `info` prints formatted message to stdout |
| `test_success_output` | `success` prints formatted message to stdout |
| `test_user_output` | `user` prints formatted message to stdout |
| `test_fail_exits` | `fail` prints message and exits non-zero |
| `test_fail_soft_no_exit` | `fail_soft` prints message but does NOT exit |
| `test_quiet_suppresses_info` | `QUIET=true` suppresses `info` output |
| `test_quiet_suppresses_success` | `QUIET=true` suppresses `success` output |
| `test_quiet_force_flag` | `info "msg" --force` still prints when `QUIET=true` |

### test_symlinks.sh

Each test uses a temp directory as `$HOME`.

| Test | What it verifies |
|------|-----------------|
| `test_link_files_creates_symlink` | `link_files` creates a symlink from src to dst |
| `test_link_files_skips_existing` | Skips when symlink already points to the same source |
| `test_copy_file_copies` | `copy_file` copies file content to destination |
| `test_copy_file_skips_identical` | Skips when destination content matches source |
| `test_copy_file_force_overwrites` | `FORCE=true` overwrites without prompting |
| `test_dry_run_link` | `DRY=true` prevents `link_files` from creating anything |
| `test_dry_run_copy` | `DRY=true` prevents `copy_file` from creating anything |
| `test_setup_symlinks_folder_files` | `setup_symlinks_folder` links top-level files to `$HOME` |
| `test_setup_symlinks_folder_bin` | `setup_symlinks_folder` links bin/ files to `$HOME/.local/bin/` |
| `test_setup_symlinks_folder_config` | `setup_symlinks_folder` links config/ dirs to `$HOME/.config/` |
| `test_setup_symlinks_folder_zshrc_copied` | `.zshrc` is copied (not symlinked) |

### test_cli.sh

Tests source or invoke `shared/bin/dotfile` and check globals/behavior.

| Test | What it verifies |
|------|-----------------|
| `test_flag_dry` | `-d` sets `DRY=true` |
| `test_flag_force` | `-f` sets `FORCE=true` |
| `test_flag_quiet` | `-q` sets `QUIET=true` |
| `test_combined_flags` | `-d -f -q` sets all three |
| `test_help_exits_zero` | `-h` prints usage and exits 0 |
| `test_unknown_command_fails` | Unknown command exits non-zero |

### test_verify.sh

Tests use a controlled environment with known tool presence/absence.

| Test | What it verifies |
|------|-----------------|
| `test_verify_tool_found` | Reports success when a tool is on PATH |
| `test_verify_tool_missing` | Reports fail_soft when a tool is missing |
| `test_verify_symlink_valid` | Detects valid symlink pointing to dotfiles dir |
| `test_verify_file_not_symlink` | Detects file that exists but isn't a symlink |
| `test_verify_error_count` | Counts errors correctly in summary |

## Usage

```bash
# Run all tests in Docker (default)
./tests/runner.sh

# Run tests directly on host (no Docker)
./tests/runner.sh --no-docker

# Run a single test file
./tests/runner.sh test_utils.sh
./tests/runner.sh --no-docker test_utils.sh
```
