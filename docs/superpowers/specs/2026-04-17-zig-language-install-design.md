# Zig language install — design spec

**Date:** 2026-04-17
**Status:** Approved (pending user spec review)
**Scope:** New `dotfile languages` subcommand with `zig` as the first language, Linux + macOS only.

## Goal

Add a `dotfile languages` subcommand that installs language toolchains by downloading verified upstream binaries into `~/.local/`, independent of the system package manager. First implementation: Zig, fetched from the official Zig community mirrors with minisign signature verification.

## Non-goals

- Windows support. `dotfile.ps1` already installs zig via scoop and is left untouched.
- Multiple language toolchains in this iteration. The umbrella structure is in place, but only `zig` is implemented.
- Version pinning / per-version `dotfile zig 0.14.1` style invocation. Always installs the latest stable from `index.json`.
- Replacing system zig (apt/pacman/brew). If the user has a system-installed zig, this script installs its own copy alongside; the user's `PATH` order decides which wins.

## CLI surface

```
dotfile languages           # install all languages (currently: zig)
dotfile languages zig       # install only zig
```

- Not run by `dotfile all` (opt-in only).
- `dotfile update` adds an `update_languages` step after `update_packages`. `update_languages` only acts on languages this script previously installed (detected by symlink target); it never touches a system / brew / scoop install.

Help text in `dotfile`'s `usage` updated to list `languages`.

## Files added / changed

- **New:** `scripts/languages.sh` — sourced by `dotfile`. Holds `install_languages`, `update_languages`, plus per-language functions.
- **Changed:** `dotfile` — `source` the new script, dispatch the `languages` subcommand (with optional second arg), call `update_languages` from `update`, mention `languages` in `usage`.
- **New:** `tests/bash/test_languages.sh` — unit tests for every new function.
- **Changed:** `tests/bash/helpers.sh` — add `mock_uname_m` (mirrors `mock_uname`) plus matching `cleanup_test_env` reset.
- **Changed:** `tests/bash/test_cli.sh` — add dispatch tests for `languages` and `languages zig`.
- **Changed:** `CLAUDE.md` — already updated in this commit to document the test framework so future work covers it.

## Install layout

```
~/.local/zig-<version>/                # version-only directory (e.g., zig-0.14.1/)
~/.local/zig-<version>/zig             # the binary
~/.local/bin/zig                       # symlink → ~/.local/zig-<version>/zig
```

The upstream tarball extracts to `zig-<arch>-<os>-<version>/` (e.g. `zig-x86_64-linux-0.14.1/`); the install step renames it to the version-only form when moving into `~/.local/`. This keeps `zig_current_installed_version`'s parsing rule simple and stable across architectures.

On upgrade: extract new version next to the old one, atomically swap the `~/.local/bin/zig` symlink with `ln -sfn`, then remove the old `~/.local/zig-*/` directory. Lets us roll back if extraction fails.

## Function inventory (`scripts/languages.sh`)

### `zig_target_triple`

Map `uname -s` × `uname -m` to Zig's tarball arch slug.

| `uname -s` | `uname -m` | Output |
|---|---|---|
| `Linux` | `x86_64` | `x86_64-linux` |
| `Linux` | `aarch64` / `arm64` | `aarch64-linux` |
| `Darwin` | `x86_64` | `x86_64-macos` |
| `Darwin` | `arm64` | `aarch64-macos` |
| anything else | — | `fail` with clear message |

### `zig_latest_stable`

Fetch `https://ziglang.org/download/index.json` via `http_get_retry` (already exists in `packages.sh`). Parse top-level keys, drop `master`, return the highest semver. Fail clearly if the document is empty or unparseable.

### `zig_current_installed_version`

Inspect `~/.local/bin/zig`. Return:

- empty if the symlink doesn't exist
- empty if it resolves outside `~/.local/zig-*/` ("foreign install" — don't touch)
- `<version>` parsed from the parent directory name otherwise

### `ensure_minisign`

If `minisign` is not on `PATH`, install via the platform's package manager (uses `detect_platform` from `platform.sh`):

- `debian` → `sudo apt install -y minisign`
- `arch` → `sudo pacman -S --needed --noconfirm minisign`
- `mac` → `brew install minisign`
- `unknown` → `fail`

Respects `$DRY` (logs intent only).

### `install_zig`

```text
1. ensure_minisign
2. triple   = zig_target_triple
3. version  = zig_latest_stable
4. tarball  = "zig-${triple}-${version}.tar.xz"
5. shasum   = expected sha256 from index.json
6. if zig_current_installed_version == version: log "already installed"; return
7. fetch community-mirrors.txt
8. for mirror in shuffled(mirrors):
     - GET {mirror}/{tarball}?source=quando-dotfiles → tmp tarball
     - GET {mirror}/{tarball}.minisig?source=quando-dotfiles → tmp sig
     - minisign -V -P "$ZIG_PUBKEY" -m <tarball> -x <sig>      # fail → continue
     - parse `file:` field from sig trusted comment            # mismatch → continue (downgrade-attack guard)
     - sha256sum <tarball> matches shasum                      # mismatch → continue
     - break
   if no mirror succeeded: fail "Could not fetch a verified Zig tarball"
9. extract to a temp dir
10. mv tmp_dir → ~/.local/zig-<version>/   (rm -rf existing first if it somehow exists)
11. ln -sfn ~/.local/zig-<version>/zig ~/.local/bin/zig
12. rm -rf old ~/.local/zig-*/ directories that aren't <version>
```

`ZIG_PUBKEY` is a hardcoded constant at the top of `languages.sh` with a comment recording the source URL (`https://ziglang.org/download/`) and the date copied. Re-check periodically (manual; no automation for key rotation in this iteration).

All filesystem mutations and network calls gated on `[[ "$DRY" == "false" ]]`. Use a `trap` on `RETURN`/`EXIT` to clean up temp files on early exit.

### `update_zig`

```text
if zig_current_installed_version == "": return    # nothing or foreign install
install_zig                                       # skip-if-current handles the no-op case
```

### `install_languages`

```text
local target="${1:-all}"
case "$target" in
  all|"") install_zig ;;
  zig)    install_zig ;;
  *)      fail "Unknown language: $target" ;;
esac
```

### `update_languages`

```text
update_zig
```

(Future languages will append more `update_*` calls here.)

## Update flow integration

In `dotfile`, after `update_packages` inside `setup_dotfiles` is unchanged (no language calls in `all`). Add `update_languages` to the body of the `update` subcommand after `update_packages`:

```bash
update)
  update_packages
  update_languages
  ;;
```

## Help text

Add to `usage`:

```
  languages [LANG]   Install language toolchains (currently: zig). LANG selects one.
```

## Tests

### New: `tests/bash/test_languages.sh`

Setup/teardown reuse `init_test_env` / `cleanup_test_env`. Each test exercises one branch.

| Test | What it verifies |
|---|---|
| `test_zig_target_triple_linux_x86_64` | `mock_uname Linux` + `mock_uname_m x86_64` → `x86_64-linux` |
| `test_zig_target_triple_linux_aarch64` | `aarch64` → `aarch64-linux` |
| `test_zig_target_triple_macos_x86_64` | Darwin x86_64 → `x86_64-macos` |
| `test_zig_target_triple_macos_aarch64` | Darwin arm64 → `aarch64-macos` |
| `test_zig_target_triple_unsupported_arch_fails` | Linux + i686 → exits non-zero |
| `test_zig_latest_stable_picks_highest` | Stub `http_get_retry` to print a fixture JSON (with `0.13.0`, `0.14.1`, `master`) → `0.14.1` |
| `test_zig_latest_stable_skips_master` | JSON containing only `master` and a stable → returns the stable |
| `test_zig_latest_stable_fails_on_empty` | Stub returns `{}` → exits non-zero |
| `test_zig_current_installed_version_none` | No symlink → empty |
| `test_zig_current_installed_version_ours_returns_version` | Pre-create `~/.local/zig-0.14.1/zig` + symlink → `0.14.1` |
| `test_zig_current_installed_version_foreign_returns_empty` | Symlink points to `/usr/bin/zig` → empty |
| `test_ensure_minisign_already_present_noop` | Fake `minisign` on `PATH`, `DRY=true` → no install attempt logged |
| `test_ensure_minisign_dry_run_arch_logs_install` | `mock_uname Linux` + arch detect, `DRY=true` → "Installing minisign" |
| `test_ensure_minisign_dry_run_debian_logs_install` | Debian-mocked → same |
| `test_ensure_minisign_dry_run_mac_logs_install` | Darwin → same |
| `test_install_zig_dry_run` | `DRY=true` → expected log lines, no network attempted |
| `test_install_zig_already_installed_short_circuits` | Pre-create symlink at the version `zig_latest_stable` (stubbed) returns → "Already installed" |
| `test_update_zig_no_op_when_not_installed` | No symlink → exits silently |
| `test_update_zig_skips_foreign_install` | Foreign symlink → exits silently |
| `test_update_zig_dry_run_when_ours` | Pre-existing "ours" install + `DRY=true` → reaches `install_zig` log path |
| `test_install_languages_dry_run` | `DRY=true install_languages` → invokes zig path |
| `test_install_languages_zig_only_arg` | `install_languages zig` → invokes zig path |
| `test_install_languages_unknown_fails` | `install_languages java` → exits non-zero |
| `test_update_languages_dry_run` | Smoke |

Stubbing approach: shadow `http_get_retry` and `curl` with bash functions inside the test scope so we never hit the network. Pattern matches existing tests that fake binaries on `PATH`.

### Changes: `tests/bash/helpers.sh`

Add `mock_uname_m` (parallels `mock_uname`) and reset its env var in `cleanup_test_env`.

### Changes: `tests/bash/test_cli.sh`

- `test_languages_command_in_help` — `--help` output contains `languages`.
- `test_dry_run_languages_command` — `bash $DOTFILE_CMD --dry languages` exits 0.
- `test_dry_run_languages_zig` — `bash $DOTFILE_CMD --dry languages zig` exits 0.

### Manual smoke test (not unit-testable)

The mirror loop, minisign verification, sha256 check, atomic extract/swap, and old-version cleanup require real network and real signing infrastructure. Smoke test plan:

1. On this Arch box: `dotfile languages zig` → verify `~/.local/bin/zig --version` works and matches the latest stable on ziglang.org.
2. Re-run: should hit the "Already installed" path instantly.
3. Force re-install by removing `~/.local/bin/zig` and `~/.local/zig-*/`, re-run.
4. Run `dotfile update` — `update_zig` should no-op (still on latest).
5. Manual downgrade attack test: hand-edit a downloaded `.minisig` file's `file:` field, re-run with that mirror forced — verify the script rejects it and tries the next mirror.
6. Repeat steps 1–4 on Mac.

## Error handling

- `set -eo pipefail` at the top of `languages.sh` (matches `packages.sh`, `extras.sh`).
- Any verification failure within a mirror iteration → `continue` to the next mirror. **Never** fall back to an unverified download.
- All temp files cleaned up on exit via `trap`.
- All user-visible errors go through the existing `fail` helper (red `[FAIL]`, exit 1).

## Open questions

None. All decisions resolved during brainstorming.

## Out of scope (future work)

- Adding more languages (Go, Rust, Python, Node) under the same umbrella.
- Caching `community-mirrors.txt` between runs.
- Verifying / rotating `ZIG_PUBKEY` automatically.
- A `dotfile uninstall <language>` complement.
