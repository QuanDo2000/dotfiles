# PowerShell (pwsh) install — design spec

**Date:** 2026-04-18
**Status:** Approved (pending user spec review)
**Scope:** Add pwsh to the default `dotfile packages` install flow on Debian/Ubuntu, Arch, and macOS. Bootstrap `yay` on Arch as the AUR helper so `powershell-bin` can be pulled from the AUR.

## Goal

After `dotfile packages` completes, `pwsh` is on PATH on all three Unix-family platforms, matching the behaviour that `dotfile.ps1` already assumes on Windows.

Each platform uses its native package manager:
- **Debian/Ubuntu:** Microsoft's apt repo, registered via `packages-microsoft-prod.deb`, then `apt install powershell`.
- **Arch:** `yay -S powershell-bin` (AUR). Requires bootstrapping `yay` first.
- **macOS:** `powershell` cask via Homebrew.

## Non-goals

- Pinning to a specific PowerShell version (always the latest the platform PM ships).
- Installing PowerShell modules, profiles, or any other pwsh configuration — scope is the binary only.
- Any change to the Windows side (`dotfile.ps1`); pwsh is already the host shell there.
- Adding a `dotfile pwsh` subcommand — pwsh is part of the baseline package install, not an opt-in.
- Using `yay` for anything other than pwsh in this change (the helper is installed, but no other packages migrate to AUR).
- Distros other than Debian-family and Arch-family on Linux.

## CLI surface

No new subcommands. pwsh installs as part of the existing flow:

```
dotfile packages          # installs pwsh alongside existing tooling
dotfile update            # re-runs apt/brew upgrade, plus setup_pwsh --update on Arch
dotfile verify            # new: asserts `pwsh` is on PATH
```

## Files added / changed

| File | Action | Responsibility |
|---|---|---|
| `scripts/packages.sh` | Modify | Add `setup_yay` and `setup_pwsh`. Wire into `install_debian`, `install_arch`, `update_debian`, `update_arch`. Add `powershell` to `MAC_BREW_CASKS`. |
| `scripts/verify.sh` | Modify | Add `pwsh` to `REQUIRED_TOOLS`. |
| `tests/bash/test_packages.sh` | Modify | Add tests for `setup_yay` and `setup_pwsh` (dry-run, already-installed, update-does-not-skip, skips-on-mac). |

No Windows-side changes.

## Per-platform implementation

### Debian/Ubuntu — `setup_pwsh [--update]`

The Microsoft repo config ships as a `.deb` that installs both the apt source list and the GPG key. This avoids hand-rolling `/etc/apt/keyrings` entries.

1. Skip the bootstrap if `/etc/apt/sources.list.d/microsoft-prod.list` already exists (idempotency guard).
2. Source `/etc/os-release`; read `ID` and `VERSION_ID`.
   - `ID=debian` → `https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb`
   - `ID=ubuntu` (or `ID_LIKE=*ubuntu*`) → `https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb`
   - Fallback: if neither matches, log and return without failing the whole install.
3. Download to a temp file via `http_get_retry`, `sudo dpkg -i`, `sudo apt update`.
4. `sudo apt install -y powershell`.

`--update` mode: skip the `.deb` bootstrap (already installed), just re-run `sudo apt install -y powershell` to let apt pull any newer version.

Install-mode fast-path: if `command -v pwsh` succeeds and no `--update`, log "Already installed pwsh" and return.

### Arch — `setup_yay` + `setup_pwsh [--update]`

**`setup_yay`** (new, called from `install_arch` before `setup_pwsh`):

1. Fast-path: if `command -v yay` succeeds, log "Already installed yay" and return.
2. Guard: if `$EUID -eq 0`, fail with "setup_yay must not run as root" — `makepkg` refuses to run as root.
3. Require `git` and `makepkg` on PATH. Both come from `base-devel` which is already in `ARCH_PACKAGES`, so in the normal install flow this is satisfied by the time `setup_yay` runs.
4. Clone `https://aur.archlinux.org/yay-bin.git` into `/tmp/yay-bin` (rm first if it already exists from a prior failed run).
5. `cd /tmp/yay-bin && makepkg -si --noconfirm`. `-s` installs pacman deps, `-i` runs `sudo pacman -U` on the built package.
6. Clean up `/tmp/yay-bin`.

**`setup_pwsh`** (Arch branch):

- Install: `yay -S --needed --noconfirm powershell-bin`.
- Update: `yay -S --noconfirm powershell-bin` (no `--needed`, so yay will rebuild/reinstall if a newer version is available).
- Install-mode fast-path: if `command -v pwsh` succeeds and no `--update`, skip.

Note: `yay -Syu` run during other update flows will also catch pwsh updates, so `setup_pwsh --update` on Arch is partly redundant — but it keeps the `update_arch` flow symmetric with `update_debian`.

### macOS — cask

Add `powershell` to `MAC_BREW_CASKS`. No new function:

```bash
MAC_BREW_CASKS=(ghostty powershell)
```

`install_mac` already calls `brew install --cask "${MAC_BREW_CASKS[@]}"`. `update_mac` already calls `brew upgrade`, which upgrades casks. `setup_pwsh` on Mac is a no-op (returns early), matching the `setup_neovim` pattern.

## Integration points in `packages.sh`

```
install_debian:
  ...existing setup_* calls...
  setup_pwsh

install_arch:
  ...existing setup_* calls...
  setup_yay
  setup_pwsh

install_mac:
  # powershell is in MAC_BREW_CASKS; no call needed

update_debian:
  ...existing --update calls...
  setup_pwsh --update

update_arch:
  ...existing --update calls...
  setup_pwsh --update

update_mac:
  # brew upgrade handles it
```

## verify.sh

```bash
REQUIRED_TOOLS=(git zsh vim nvim tmux fzf fd rg lazygit zoxide pwsh)
```

The existing `_check_tool` loop picks it up with no further code changes.

## Tests

All in `tests/bash/test_packages.sh`, following the existing `setup_*` test conventions.

### `setup_yay`

- `test_setup_yay_dry_run` — `DRY=true`; assert output contains "yay" and "Finished".
- `test_setup_yay_already_installed` — fake `yay` on PATH via `$HOME/.local/bin/yay`; assert "Already installed yay".
- `test_setup_yay_refuses_as_root` — stub `EUID=0` via a local variable override; assert failure message mentions "root". *(If stubbing `$EUID` turns out to be awkward in practice during implementation, drop this test — the guard itself is trivial.)*

### `setup_pwsh`

- `test_setup_pwsh_dry_run_debian` — stub `detect_platform` to echo `debian`; `DRY=true`; assert "pwsh" and "Finished".
- `test_setup_pwsh_dry_run_arch` — stub `detect_platform` to echo `arch`; `DRY=true`; assert "pwsh" and "Finished".
- `test_setup_pwsh_skips_on_mac` — stub `detect_platform` to echo `mac`; `DRY=false`; assert output is empty (early-return no-op).
- `test_setup_pwsh_already_installed` — fake `pwsh` on PATH; `DRY=false`; stub platform as `debian`; assert "Already installed pwsh".
- `test_setup_pwsh_update_dry_run` — `--update` with platform stubbed; assert "pwsh" and "Finished".
- `test_setup_pwsh_update_does_not_skip` — `--update` with `pwsh` on PATH; assert output does NOT contain "Already installed".

### Helper pattern for platform stubbing

Tests that need a non-host platform override `detect_platform` locally by redefining the function inside the test:

```bash
test_setup_pwsh_dry_run_arch() {
  detect_platform() { echo "arch"; }
  DRY=true
  local output
  output=$(setup_pwsh 2>&1)
  assert_contains "$output" "pwsh"
  assert_contains "$output" "Finished"
}
```

No change to `tests/bash/helpers.sh`.

### CLI dispatch

No new subcommand, so no new test in `test_cli.sh`.

## Risk & rollback

- **Debian VERSION_ID fallthrough:** if the user is on a Debian-family distro where `packages.microsoft.com` has no matching `config/<id>/<version>/packages-microsoft-prod.deb` (e.g. an unreleased rolling variant, or an Ubuntu LTS that just shipped before Microsoft published config), the install logs a skip and the rest of `install_debian` completes. `verify` will then flag `pwsh` as missing; user re-runs manually or waits.
- **yay bootstrap on Arch:** a failed `makepkg -si` mid-run leaves `/tmp/yay-bin` lying around. The function removes the dir before cloning so a re-run recovers cleanly.
- **Mac cask on CI without brew:** same behaviour as every other `MAC_BREW_CASKS` entry — dry-run skips it, real install relies on `brew` being present.

Rollback is per-platform:
- Debian: `sudo apt remove powershell && sudo rm /etc/apt/sources.list.d/microsoft-prod.list`.
- Arch: `yay -R powershell-bin`. yay itself can stay.
- Mac: `brew uninstall --cask powershell`.
