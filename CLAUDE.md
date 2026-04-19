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
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam, jank)
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

## Tests

Tests live under `tests/` with one suite per platform.

```bash
bash tests/bash/runner.sh                  # all bash tests (runs in Docker by default)
bash tests/bash/runner.sh --no-docker      # all bash tests on host (faster while iterating)
bash tests/bash/runner.sh test_packages.sh # single file
pwsh tests/powershell/runner.ps1           # PowerShell tests (Windows / pwsh)
```

### Bash test pattern

- One `test_<module>.sh` per `scripts/<module>.sh`. Each `test_*` function is auto-discovered by the runner.
- Source `tests/bash/helpers.sh` at the top, then use `setup`/`teardown` to call `init_test_env` / `cleanup_test_env`. The helper creates a throwaway `$HOME` under a temp dir and exports `DRY`/`QUIET`/`FORCE`.
- Source the script under test via `source_scripts utils.sh <module>.sh` (always pulls in `platform.sh` automatically).
- Mock OS detection with `mock_uname Linux` / `mock_uname Darwin` (auto-cleared by `cleanup_test_env`).
- Assertions: `assert_equals`, `assert_contains`, `assert_file_exists`, `assert_symlink`, `assert_exit_code`. Failures append to `$ERROR_FILE`; tests do not abort on first failure.
- Default exercise paths: `DRY=true` smoke run, "already installed" short-circuit, `--update` mode does not skip when present, and any platform-specific branches.

### PowerShell test pattern

- One `test_<feature>.ps1` per logical area. Source `tests/powershell/helpers.ps1` and dot-source `dotfile.ps1 -NoMain` to load functions without triggering self-elevation or main dispatch.
- Same dry-run / branch-coverage philosophy as bash tests.

### When adding a new subcommand or script

Add a `tests/bash/test_<name>.sh` (and `tests/powershell/test_<name>.ps1` if Windows-relevant) covering the dry-run path, the skip-if-already-installed path, and any platform branching. Also add a CLI dispatch test in `test_cli.sh` (e.g., `--dry <newcommand>` exits 0 and the help text mentions it).
