# Jank language install — design spec

**Date:** 2026-04-18
**Status:** Approved (pending user spec review)
**Scope:** Add Jank as the fourth language under `dotfile languages [LANG]`. Linux + macOS only — strict OS subset (Apple Silicon mac, Ubuntu, Arch). Bash side only; `dotfile.ps1` untouched (Jank doesn't support Windows).

## Goal

Install Jank via each platform's official package channel:
- **macOS (Apple Silicon)**: Homebrew tap `jank-lang/jank/jank`.
- **Ubuntu (24.04+)**: Custom PPA at `ppa.jank-lang.org` (one-time GPG key + sources.list setup).
- **Arch**: AUR (`jank-bin`) via the existing `setup_yay` helper.

Lenient umbrella behaviour: `install_jank` on an unsupported platform prints a visible "Skipping Jank: not supported on this platform" message and exits 0, so `dotfile languages` (the umbrella) keeps succeeding.

## Non-goals

- GitHub-binary download / SHA-256 verification (Jank publishes no GitHub release tarballs — install is package-manager-only). Trust = the platform PM's own signing model.
- The `~/.local/<lang>-<version>/` + symlink layout used by Zig/Odin/Gleam. Jank goes wherever the system PM installs it.
- Precise version tracking: Jank has no `--version` CLI flag, so `jank_current_installed_version` collapses to "is it installed at all" (returns the sentinel string `installed` or empty).
- Building from source via `jank-git` (AUR) or `jank-lang/jank/jank-git` (Homebrew tap).
- Windows support (Jank doesn't support Windows upstream).
- Generic Debian, older Ubuntu (22.04 and earlier), Intel macOS — all explicitly broken upstream (libstdc++ too old for C++20, no x86 brew binaries published).

## CLI surface

Existing umbrella gains a `jank` arm:

```
dotfile languages           # install zig + odin + gleam + jank
dotfile languages jank      # install only jank
dotfile update              # update all four, only acting on installs we own
```

`dotfile languages jank` on an unsupported platform prints the skip message and exits 0 (same lenient behaviour as the umbrella — predictability over strictness).

## Files added / changed

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Modify | Add `jank_check_platform`, `jank_current_installed_version`, `install_jank`, `update_jank`, `_install_jank_ppa`. Extend `install_languages` and `update_languages`. |
| `tests/bash/test_languages.sh` | Modify | ~13 new/changed tests. |
| `tests/bash/test_cli.sh` | Modify | Add `test_dry_run_languages_jank`. |
| `dotfile` | Modify | Update `usage` text: `(zig, odin, gleam)` → `(zig, odin, gleam, jank)`. |
| `CLAUDE.md` | Modify | Same one-line update in Key Commands. |

## Function inventory

### `jank_check_platform`

Returns 0 if Jank can be installed on this host, non-zero otherwise. Does **not** call `fail` — caller decides whether to error or skip.

To make Ubuntu detection testable without writing to `/etc/os-release`, the function accepts an optional `$1` that overrides the os-release ID lookup. Tests inject directly; production code passes nothing.

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

### `jank_current_installed_version`

```bash
# Returns "installed" if jank is on PATH, empty otherwise.
# Jank has no --version flag, so we can't track precise versions like with
# Zig/Odin/Gleam. The string "installed" is a sentinel value.
jank_current_installed_version() {
  command -v jank >/dev/null 2>&1 && echo "installed"
}
```

### `_install_jank_ppa`

Idempotent — only runs the GPG-key + sources.list addition + `apt update` if `/etc/apt/sources.list.d/jank.list` doesn't already exist.

```bash
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
```

### `install_jank`

```bash
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

### `update_jank`

Silently no-ops on unsupported platforms (matches the existing `update_zig`/`update_odin`/`update_gleam` "silent if nothing to do" pattern). Visible logs only when there's actual update work to consider.

```bash
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

### Umbrella changes

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

update_languages() {
  update_zig
  update_odin
  update_gleam
  update_jank
}
```

## Tests

### Additions to `tests/bash/test_languages.sh`

| Test | Purpose |
|---|---|
| `jank_check_platform_mac_arm64_succeeds` | `mock_uname Darwin` + `mock_uname_m arm64` + stub `detect_platform → mac` → returns 0 |
| `jank_check_platform_mac_x86_64_returns_nonzero` | Intel Mac → returns 1, no fail/output |
| `jank_check_platform_arch_succeeds` | `detect_platform → arch` → returns 0 |
| `jank_check_platform_ubuntu_via_arg_succeeds` | `jank_check_platform ubuntu` (override) on `detect_platform → debian` → returns 0 |
| `jank_check_platform_debian_via_arg_returns_nonzero` | `jank_check_platform debian` (override) on `detect_platform → debian` → returns 1 |
| `jank_check_platform_unknown_returns_nonzero` | `detect_platform → unknown` → returns 1 |
| `jank_current_installed_version_none` | No `jank` on PATH (use `command()` shadow) → empty |
| `jank_current_installed_version_present` | Fake `jank` on PATH → "installed" |
| `install_jank_unsupported_platform_skips` | Mocked Intel mac → "Skipping Jank" log line + exit 0 |
| `install_jank_dry_run_arch` | DRY=true on mocked arch → expected log lines, no yay call |
| `install_jank_already_installed_short_circuits` | Fake `jank` on PATH → "Already installed Jank" log line |
| `update_jank_no_op_when_not_installed` | No `jank` on PATH → silent + exit 0 |
| `update_jank_unsupported_platform_no_op` | Mocked Intel mac → silent + exit 0 |
| `update_jank_dry_run_when_installed` | Fake `jank` on PATH + DRY=true on arch → expected log lines |
| Tighten existing umbrella tests | `_dry_run` and `_all_arg` add `assert_contains "Installing Jank"`. New `_jank_only_arg` test (asserts NO Zig/Odin/Gleam fall-through). |

The Ubuntu install path is not unit-tested in detail — `_install_jank_ppa` does sudo+gpg+curl which has no clean stub-points without major refactor. Manual smoke covers it.

### Additions to `tests/bash/test_cli.sh`

```bash
test_dry_run_languages_jank() {
  is_windows_bash && return 0
  assert_exit_code 0 bash "$DOTFILE_CMD" --dry languages jank
}
```

### Manual smoke test (Arch host)

1. **Fresh install:**
   ```bash
   bash ./dotfile languages jank
   command -v jank
   ```
   Expected: yay (installed by `setup_yay` if missing) builds + installs `jank-bin`. Final `command -v jank` succeeds.
   *Note: yay's `-S` will prompt for sudo for the package install — this won't run in Claude's TTY-less shell, so the user runs the smoke step in their own terminal.*

2. **Re-install short-circuits:**
   ```bash
   bash ./dotfile languages jank
   ```
   Expected: "Already installed Jank".

3. **Update is idempotent:**
   ```bash
   bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_jank'
   ```
   Expected: `yay -Syy && yay -S jank-bin` runs; succeeds whether or not a new version exists.

4. **Umbrella runs all four:**
   ```bash
   bash ./dotfile languages
   ```
   Expected: Zig + Odin + Gleam each short-circuit (already installed), Jank either short-circuits or runs.

5. **macOS smoke deferred** (no Mac available).
6. **Ubuntu smoke deferred** (no Ubuntu host available).

## Error handling

- `set -eo pipefail` already at top of `languages.sh`.
- `fail` for unrecoverable errors (download/install failure, repo setup failure).
- `jank_check_platform` returns non-zero for unsupported platforms but does NOT call fail — it lets `install_jank`/`update_jank` decide how to handle the result.
- `install_jank` on unsupported platforms exits 0 with a visible "Skipping Jank" message + a docs URL.
- `update_jank` on unsupported platforms exits 0 silently (no message — matches the other update_* functions).

## CLAUDE.md update

```
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam, jank)
```

## Open questions

None. All decisions resolved during brainstorming.

## Out of scope / future work

- Source-build path (`jank-git` AUR / `jank-lang/jank/jank-git` Homebrew tap).
- Pinning jank versions.
- Windows / Debian / Intel-mac / older-Ubuntu support — all blocked upstream.
- A `dotfile uninstall <language>` complement.
- Adding a `jank --version` parse if upstream ever ships one — would let us track precise versions like Zig/Odin/Gleam.
