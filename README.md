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

After Home Manager applies, the `dotfile` command is available in your PATH:

```bash
dotfile
```

### Linux with Nix/Home Manager

Arch and Debian use the native package manager only for bootstrap packages,
then use this repo's pinned flake to install Home Manager user tools and config:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/dotfile packages
~/dotfiles/dotfile all
```

The Linux Home Manager output is `${username}@linux`, where `username` comes
from `config/host.nix`. `dotfile packages` installs Lix/Nix if missing, uses
an existing `home-manager` when available, and falls back to the pinned
`~/dotfiles#home-manager` app for bootstrap. Lix installer and package artifacts
are used only after their tracked SHA-256 matches; review changes from
`dotfile lix-installer` before committing updated installer pins.

### Windows

Run the following in PowerShell as Administrator:

```powershell
git clone https://github.com/QuanDo2000/dotfiles.git $HOME\Documents\Projects\dotfiles
& $HOME\Documents\Projects\dotfiles\dotfile.ps1
```

### Unix Commands

```bash
dotfile [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Refresh all managed dependency pins, validate, and activate
              Update only AI tools and configs with `update ai`
  packages    Install system packages only
  obsidian    Bootstrap Obsidian Sync login and vault setup
  codex       Update pinned Codex release package
  lix-installer
              Update pinned Lix installer checksums
  obsidian-headless
              Update pinned Obsidian Headless package
  doctor [--fast]
              Detect dotfile and Nix issues

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite files and approve validated dependency activation
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

### Windows Commands

```powershell
dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Update system packages
              Update only AI tools and configs with `update ai`
  packages    Install all managed packages only
  ai          Install AI tools and shared skills
  doctor      Detect Windows installation issues
  verify      Verify installation

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files without prompting
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

Note: Unix dotfiles are managed by Home Manager. `~/.zshrc` is generated from `config/unix/.zshrc.base`.

Run `./scripts/check.sh` from the repo root before pushing changes.

Note: Home Manager seeds `~/.codex/config.toml` as a writable file for Codex
runtime preferences and owns shared global skills under `~/.agents/skills/`.
Codex discovers that standard location natively; Pi includes it through its
settings. Windows copies the same reviewed, vendored skill set through
`dotfile.ps1 ai`; no remote skill installer runs during setup. Agent-specific
plugins, packages, hooks, and generated runtime state
such as `skills-lock.json`, caches, and sessions stay native and out of the repo.

Note: Home Manager owns the `lazy.nvim` bootstrap package, and tracked
`lazy-lock.json` pins raw Neovim plugin state. On Unix,
Home Manager supplies the `fff.nvim` backend from hash-pinned release assets;
`dotfile packages` and `dotfile update` sync plugin source and link it without runtime
downloads or compilation. Failures are reported after the package operation.

Windows installs Neovim and the locked raw plugin set but does not enable or install `fff.nvim`.

Note: Home Manager owns the `obsidian-headless` CLI and `obsidian-sync` user service on Linux. `dotfile obsidian` bootstraps login/vault setup and restarts the managed service; it reuses an existing configured vault under `~/Documents` unless `-f` is passed.

Note: Home Manager owns tracked Obsidian settings from `config/shared/obsidian`
under `~/Documents/Sync/.obsidian`. Plugin bundles, themes, workspace state,
bookmarks, starred files, recent files, and Electron app state stay out of the
repo.

## Provisioning a fresh NixOS machine

On a freshly-installed NixOS box:

```bash
nix-shell -p git --run 'git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles && cd ~/dotfiles && bash ./dotfile packages'
```

Per-machine values live in tracked `config/host.nix`; hardware settings live in
tracked `config/hardware-configuration.nix`. Edit those files before the first
rebuild if the username, hostname, timezone, NixOS stateVersion, disks, or CPU
settings differ. Then `bash ./dotfile all` for the rest of the dotfiles.
The NixOS flake target is `#${hostName}` from `config/host.nix`; the current
tracked host uses `#nixos`.

On a brand-new machine, run this once before the first `switch` to confirm the
config evaluates:

```bash
sudo nixos-rebuild build --flake ~/dotfiles#${hostName}
```

After provisioning, use `dotfile update` to refresh every repository-managed
dependency: Nix inputs, release archives, npm closures, native FFF assets,
Windows Scoop/font pins, vendored skills, and Neovim plugins. It runs full
checks, shows the resulting uncommitted diff, and requires confirmation before
activation; non-interactive runs must pass `--force`. Use `dotfile update ai`
to update only tracked AI configs, Codex and Pi release pins, managed AI
packages, and Pi extensions. On NixOS the full update ends with:

```bash
nix flake update --flake ~/dotfiles
sudo nixos-rebuild switch --flake ~/dotfiles#${hostName}
```

Commit all generated pin and lock changes after successful activation and CI
to preserve the reviewed dependency set.

On macOS it uses existing `darwin-rebuild` when available:

```bash
sudo HOME=/var/root darwin-rebuild switch --flake ~/dotfiles#mac
```

If `darwin-rebuild` is not installed yet, it bootstraps through the pinned
`~/dotfiles#darwin-rebuild` app.

The `dotfile` command itself is installed by Home Manager on NixOS/macOS; use
`./dotfile` from the repo until the first rebuild has switched successfully.

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
