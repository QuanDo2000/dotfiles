# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Personal dotfiles repo for provisioning new Linux/macOS/Windows machines. The installer clones this repo to `~/dotfiles` and runs shell scripts to install packages, set up extras (zsh plugins, tmux plugins, starship prompt), and create symlinks.

## Key Commands

```bash
dotfile                      # Full setup (packages -> extras -> symlinks)
dotfile symlinks             # Create symlinks only
dotfile packages             # Install system packages only
dotfile extras               # Install zsh plugins, tmux plugins, starship prompt
dotfile verify               # Verify installation
dotfile update               # Update system packages and language toolchains
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam, jank)
dotfile -d <command>         # Dry run
dotfile -f <command>         # Force overwrite existing files
```

## Architecture

- **dotfile** - Unix entry point at the repo root. Sources all scripts from `scripts/`, parses CLI flags, dispatches to subcommands. Symlinked into `$HOME/.local/bin/` by `setup_symlinks`.
- **dotfile.ps1** - Windows equivalent (PowerShell) at the repo root. Same subcommand structure; symlinked into `$HOME\.local\bin\` by `SetupSymlinks`.
- **scripts/** - Modular bash scripts sourced by the unix `dotfile`:
  - `utils.sh` - Logging helpers (`info`, `success`, `fail`, `user`). Sourced first with no dependencies.
  - `packages.sh` - OS-specific package installation (apt/pacman/brew).
  - `extras.sh` - zsh plugins (cloned to `~/.local/share/zsh/plugins`) and the directly-cloned tmux plugins (tmux-yank, catppuccin); no tmux plugin manager (sensible/pain-control are inlined in `.tmux.conf`). The prompt is starship (config at `config/shared/starship/starship.toml`, symlinked to `~/.config/starship.toml` on all platforms).
  - `symlinks.sh` - Links dotfiles to `$HOME`. Files in `bin/` directories under each platform layer are symlinked into `$HOME/.local/bin/`.
  - `verify.sh` - Post-install checks.

## Dotfile Layers

Platform config lives under `config/`. Symlinks are created in priority order by `setup_symlinks`:

1. **config/shared/** - Cross-platform configs (`.gitconfig`, `.vimrc`, neovim config).
2. **config/unix/** - Linux/macOS-specific (`.zshrc.base`, `.tmux.conf`, ghostty, hyprland, waybar, lazygit, fcitx5).
3. **config/mac/** - macOS-only (`.zshrc.mac`), applied only when `uname == Darwin`.
4. **config/windows/** - Windows-specific (PowerShell profile, Windows Terminal settings). Used by `dotfile.ps1`.
5. **config/nixos/** - NixOS-only. `configuration.nix` is a tracked full-desktop system config. `dotfile packages` symlinks it to `/etc/nixos/configuration.nix` and runs `nixos-rebuild switch`. Per-machine values (username, hostname, timezone, stateVersion) are auto-detected on first run, confirmed interactively when a TTY is present, and written to `/etc/nixos/machine.nix` (not tracked); `configuration.nix` imports them by absolute path. `hardware-configuration.nix` is used in place from `/etc/nixos` and is not tracked. App config files (hyprland, waybar, etc.) are NOT ported into Nix - they stay symlinked dotfiles via `dotfile symlinks`. On NixOS the imperative `setup_*` installers are skipped; packages come from the rebuild.

Files in `config/` subdirectories of each platform layer are symlinked into `~/.config/`. Top-level dotfiles are symlinked directly to `$HOME`.

Both loose files and directories under a layer's `config/` are linked into `~/.config/` by their basename (e.g. `config/shared/config/starship.toml` -> `~/.config/starship.toml`, `config/shared/config/nvim/` -> `~/.config/nvim/`).

Carveouts in `setup_symlinks` handle individual files in dotfolders we don't want to link wholesale: `config/shared/.ssh/config` -> `~/.ssh/config`, `config/shared/ai/claude/settings.json` -> `~/.claude/settings.json`, and `config/shared/ai/codex/config.toml` -> `~/.codex/config.toml`. Note codex rewrites its `config.toml` at runtime, so that symlink can periodically dirty the repo. Only the listed files are linked - caches, sessions, credentials, `node_modules`, and plugin runtime artifacts are left alone.

`~/.zshrc` is the one shell file that is **machine-local, not symlinked**. All tracked zsh config lives in `config/unix/.zshrc.base` (symlinked to `~/.zshrc.base`). `setup_symlinks` calls `_ensure_local_zshrc`, which creates `~/.zshrc` if missing - a stub that just sources `~/.zshrc.base` - and replaces it if an older setup left it symlinked into the repo. This keeps the repo clean: tool installers (nvm, bun, pnpm, ...) append their lines to the real `~/.zshrc` below the source line, so per-machine edits never modify tracked files. Existing local `~/.zshrc` files are never overwritten.

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

## Migrating an existing machine off oh-my-zsh

oh-my-zsh is no longer used. On a machine provisioned before this change:

1. `dotfile packages`  # installs starship
2. `dotfile zsh`       # clones plugins to ~/.local/share/zsh/plugins
3. `dotfile symlinks`  # links ~/.config/starship.toml and the new .zshrc files
4. `rm -rf ~/.oh-my-zsh`  # optional: remove the now-unused framework

On Windows, `oh-my-posh` can likewise be uninstalled: `winget uninstall JanDeDobbeleer.OhMyPosh`.
