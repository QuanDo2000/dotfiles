# dotfiles

Personal setup scripts and configuration files for new machines.

## Requirements

### Linux / macOS

- `sudo`, `curl`, and `git`

### Windows

- PowerShell 5.1+ (Windows PowerShell) or PowerShell 7 (`pwsh`)
- Must be run from an **Administrator** PowerShell (required to create symlinks).
  The script self-elevates via `Start-Process -Verb RunAs` if needed.
- `git` (install via `winget install Git.Git` first, or use the bundled Git that ships with Windows Terminal / Scoop)
- The script installs `winget` packages and bootstraps `scoop`; no pre-install required.

### Configuration

- `DOTFILES_DIR` environment variable may be set to override where the repo is
  expected to live. Defaults:
  - Linux/macOS: `$HOME/dotfiles`
  - Windows: the parent of the `dotfile.ps1` script location.

## Usage

### Linux / macOS

First-time setup:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/dotfile
```

After symlinks are created, the `dotfile` command is available in your PATH:

```bash
dotfile
```

### Windows

Run the following in PowerShell as Administrator:

```powershell
git clone https://github.com/QuanDo2000/dotfiles.git $HOME\Documents\Projects\dotfiles
& $HOME\Documents\Projects\dotfiles\dotfile.ps1
```

### Commands

```
dotfile [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update      Update system packages and language toolchains
  packages    Install system packages only
  extras      Install zsh and tmux plugins
  symlinks    Create symlinks only
  obsidian    Set up Obsidian headless sync (Linux only; runs separately from 'all')
  languages [LANG]  Install language toolchains (zig, odin, gleam, jank)
  verify      Verify installation

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files without prompting
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

Note: `.zshrc` is machine-local (not symlinked) so local installer edits don't dirty the repo. It sources the tracked `~/.zshrc.base`.

## Provisioning a fresh NixOS machine

On a freshly-installed NixOS box (so `/etc/nixos/hardware-configuration.nix`
already exists):

```bash
nix-shell -p git --run 'git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles && cd ~/dotfiles && sudo bash ./dotfile packages'
```

On the first run, per-machine values (username, hostname, timezone, NixOS
stateVersion) are auto-detected and you confirm or override each; they're saved
to `/etc/nixos/machine.nix`. `hardware-configuration.nix` is used in place. Later
runs are silent. Then `sudo bash ./dotfile all` for the rest of the dotfiles
(symlinks, plugins).

On a brand-new machine, run `sudo nixos-rebuild build` once before the first
`switch` to confirm the config evaluates. If your channel is older than
nixos-unstable / 25.05, `ghostty` and `codex` are skipped automatically
rather than failing the build.

## Testing

Tests run in a Docker container to avoid touching your host filesystem. Requires Docker.

```bash
./tests/bash/runner.sh                    # Run all tests in Docker
./tests/bash/runner.sh test_utils.sh      # Run a single test file
./tests/bash/runner.sh --no-docker        # Run directly on host (no Docker)
```

PowerShell tests (Windows):

```powershell
./tests/powershell/runner.ps1
```
