# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles repo for provisioning new Linux/macOS/Windows machines. The installer clones this repo to `~/dotfiles` and runs shell scripts to install packages, set up extras (oh-my-zsh, tmux plugins), and create symlinks.

## Key Commands

```bash
dotfile                      # Full setup (packages → extras → symlinks)
dotfile symlinks             # Create symlinks only
dotfile packages             # Install system packages only
dotfile extras               # Install oh-my-zsh, zsh plugins, tmux plugins
dotfile verify               # Verify installation
dotfile -d <command>         # Dry run
dotfile -f <command>         # Force overwrite existing files
```

## Architecture

- **dotfile** — Unix entry point at the repo root. Sources all scripts from `scripts/`, parses CLI flags, dispatches to subcommands. Symlinked into `$HOME/.local/bin/` by `setup_symlinks`.
- **dotfile.ps1** — Windows equivalent (PowerShell) at the repo root. Same subcommand structure; symlinked into `$HOME\.local\bin\` by `SetupSymlinks`.
- **scripts/** — Modular bash scripts sourced by the unix `dotfile`:
  - `utils.sh` — Logging helpers (`info`, `success`, `fail`, `user`). Sourced first with no dependencies.
  - `packages.sh` — OS-specific package installation (apt/pacman/brew).
  - `extras.sh` — oh-my-zsh, zsh plugins, tmux plugin manager.
  - `symlinks.sh` — Links/copies dotfiles to `$HOME`. `.zshrc` files are **copied** (not symlinked) so local edits don't pollute the repo. Files in `bin/` directories under each platform layer are symlinked into `$HOME/.local/bin/`.
  - `verify.sh` — Post-install checks.

## Dotfile Layers

Platform config lives under `config/`. Symlinks are created in priority order by `setup_symlinks`:

1. **config/shared/** — Cross-platform configs (`.gitconfig`, `.vimrc`, neovim config).
2. **config/unix/** — Linux/macOS-specific (`.zshrc.base`, `.tmux.conf`, ghostty, hyprland, waybar, lazygit, fcitx5).
3. **config/mac/** — macOS-only (`.zshrc.mac`), applied only when `uname == Darwin`.
4. **config/windows/** — Windows-specific (PowerShell profile, Windows Terminal settings). Used by `dotfile.ps1`.

Files in `config/` subdirectories of each platform layer are symlinked into `~/.config/`. Top-level dotfiles are symlinked directly to `$HOME`.

## Global Variables

Scripts share state via exported globals: `DRY`, `QUIET`, `FORCE`. These are set by `dotfile` CLI flags and checked throughout all sourced scripts.
