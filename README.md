# dotfiles

Personal setup scripts and configuration files for new machines.

## Requirements

- `sudo`, `curl`, and `git`

## Usage

### Linux / macOS

```bash
bash <(curl -s https://raw.githubusercontent.com/QuanDo2000/dotfiles/main/install.sh)
```

Or if already cloned:

```bash
cd ~/dotfiles
./install.sh
```

### Windows

Run the following in PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process
iwr -useb https://raw.githubusercontent.com/QuanDo2000/dotfiles/main/install.ps1 | iex
```

### Commands

```
./install.sh [OPTIONS] [COMMAND]

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
  -h, --help  Show this help message
```
