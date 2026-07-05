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

### Arch Linux with Nix/Home Manager

Arch uses `pacman` only for bootstrap packages, then uses this repo's pinned
flake to install Home Manager user tools and config:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/dotfile packages
~/dotfiles/dotfile all
```

The Arch Home Manager output is `${username}@arch`, where `username` comes from
`config/host.nix`. `dotfile packages` installs Lix/Nix if missing and runs the
pinned `~/dotfiles#home-manager` app; it does not use floating
`home-manager/master`.

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
  obsidian    Set up Obsidian headless sync (Arch auto-runs during 'all' when ready)
  languages [LANG]  Install language toolchains (zig, odin, gleam, jank)
  verify      Verify core Unix symlinks

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files without prompting
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

Note: `.zshrc` is machine-local (not symlinked) so local installer edits don't dirty the repo. It sources the tracked `~/.zshrc.base`.

Note: `dotfile obsidian` reuses an existing configured vault under `~/documents/obsidian` and skips interactive Sync setup unless `-f` is passed.

## Provisioning a fresh NixOS machine

On a freshly-installed NixOS box:

```bash
nix-shell -p git --run 'git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles && cd ~/dotfiles && sudo bash ./dotfile packages'
```

Per-machine values live in tracked `config/host.nix`; hardware settings live in
tracked `config/hardware-configuration.nix`. Edit those files before the first
rebuild if the username, hostname, timezone, NixOS stateVersion, disks, or CPU
settings differ. Then `sudo bash ./dotfile all` for the rest of the dotfiles.

On a brand-new machine, run `sudo nixos-rebuild build --flake ~/dotfiles#nixos`
once before the first `switch` to confirm the config evaluates.

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
