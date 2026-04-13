# dotfiles

Personal setup scripts and configuration files for new machines.

## Requirements

- `sudo`, `curl`, and `git`

## Usage

### Linux / macOS

First-time setup:

```bash
git clone https://github.com/QuanDo2000/dotfiles.git ~/dotfiles
~/dotfiles/shared/bin/dotfile
```

After symlinks are created, the `dotfile` command is available in your PATH:

```bash
dotfile
```

### Windows

Run the following in PowerShell as Administrator:

```powershell
git clone https://github.com/QuanDo2000/dotfiles.git $HOME\Documents\Projects\dotfiles
& $HOME\Documents\Projects\dotfiles\windows\bin\dotfile.ps1
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
./tests/runner.sh                    # Run all tests in Docker
./tests/runner.sh test_utils.sh      # Run a single test file
./tests/runner.sh --no-docker        # Run directly on host (no Docker)
```
