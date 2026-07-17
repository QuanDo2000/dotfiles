# Remaining Windows Parity

## Goal

Close the remaining package lifecycle and writable Codex configuration gaps
without enabling Unix-only services or FFF on Windows.

## Package lifecycle

- Add `GnuPG.Gpg4win` to the Winget manifest because the tracked Windows Git
  config points to Gpg4win.
- Add one `InstallManagedPackages` flow that installs Winget packages, Scoop
  packages, Node LTS, Codex, codebase-memory-mcp, Pi, and their writable seeds.
  Both `all` and `packages` use it.
- `update` pulls the repository, calls `InstallPackages` so newly declared
  Winget packages are installed before upgrades, then updates Scoop, Node, and
  AI tools and runs the existing post-update doctor.
- Do not add a Windows preflight doctor: its missing-package checks would block
  the update operation that repairs those packages.

## Writable Codex configuration

Create `config/windows/ai/codex/config.toml` as the Windows seed. It keeps the
shared user-facing settings and plugin configuration, omits Unix project paths
and FFF, and launches codebase-memory-mcp directly rather than through
`/usr/bin/env`.

Add `SyncCodexConfig` using the existing `scripts/seed_merge/codex.py` behavior:
copy the seed as a regular writable file when `%USERPROFILE%\.codex\config.toml`
is absent; otherwise compare the live file and update the tracked Windows seed
when the checkout is writable. Run it from `InstallAi`. Doctor requires the
live Codex config to exist and remain a regular file rather than a symlink.

## Documentation and exclusions

Update the README Windows command list to include `doctor` and describe
`packages` as installing the complete managed package set.

Keep FFF, global AGENTS links, Unix shared skills, zsh/tmux, Obsidian Headless,
and Linux desktop services excluded from Windows.

## Testing

Use the existing PowerShell runner. Add focused regressions for Gpg4win,
complete `packages` dispatch, repository-aware `update`, writable Codex seed
creation, and doctor validation. Run the focused suites, the full PowerShell
suite, a dry run, one real `dotfile all`, and standalone `dotfile doctor`.
