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
  packages    Install system packages only
  extras      Install oh-my-zsh, zsh plugins, tmux plugins
  zsh         Install oh-my-zsh and zsh plugins
  tmux        Install tmux plugins
  symlinks    Create symlinks only
  verify      Verify installation

Options:
  -d, --dry   Dry run (no changes made)
  -f, --force Overwrite existing files without prompting
  -q, --quiet Only show errors
  -h, --help  Show this help message
```

Note: `.zshrc` is **copied** into `$HOME` (not symlinked) so local edits don't propagate back into the repo. All other dotfiles are symlinked.

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
