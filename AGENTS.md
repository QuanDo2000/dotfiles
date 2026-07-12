# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Overview

Personal dotfiles repo for provisioning new Linux/macOS/Windows machines. The Unix installer clones this repo to `~/dotfiles` and runs Nix-managed package updates; Home Manager owns Unix links and shell/tool extras.

## Key Commands

```bash
dotfile                      # Full setup
dotfile packages             # Install system packages only
dotfile doctor               # Detect dotfile and Nix issues
dotfile update               # Update Nix-managed packages
dotfile obsidian             # Bootstrap Obsidian Sync login and vault setup
dotfile codex                # Update pinned Codex release package
dotfile obsidian-headless    # Update pinned Obsidian Headless package
dotfile -d <command>         # Dry run
dotfile -f <command>         # Force overwrite existing files
```

## Git Signing

If `git commit` hangs or fails because signing needs a passphrase, do not bypass signing by default. Tell the user to run `printf test | gpg --clearsign >/dev/null` to unlock/cache the GPG passphrase, then retry the commit after they confirm it is done.

## Architecture

- **dotfile** - Unix entry point at the repo root. Sources the needed scripts from `scripts/`, parses CLI flags, dispatches to subcommands. Symlinked into `$HOME/.local/bin/` by Home Manager on Linux/macOS.
- **dotfile.ps1** - Windows equivalent (PowerShell) at the repo root. Windows keeps its own `verify` command; Windows-only symlink and extra setup runs inside `all`. Symlinked into `$HOME\.local\bin\` by `SetupSymlinks`.
- **scripts/** - Modular bash scripts sourced by the unix `dotfile`:
  - `utils.sh` - Logging helpers (`info`, `success`, `fail`, `user`). Sourced first with no dependencies.
  - `packages.sh` - OS-specific package installation (apt/pacman only for Linux bootstrap packages, NixOS flakes, existing nix-darwin or pinned nix-darwin bootstrap on macOS).
  - `doctor.sh` - Health checks for Home Manager conflicts, core Unix links, Nix-managed tools, and flake targets.
  - `obsidian.sh` - Interactive Obsidian Sync bootstrap and service restart; Home Manager owns the Linux `obsidian-headless` package and `obsidian-sync` unit file.

## Dotfile Layers

Platform config lives under `config/`. Unix links are managed by Home Manager from `config/home.nix`:

1. **config/shared/** - Cross-platform configs (neovim, starship, jj, SSH, AI tool seeds, Obsidian settings). Neovim and LazyVim remain cross-platform, but the `fff.nvim` plugin/backend is Unix-only and disabled on Windows. Git settings for Linux/macOS are declared through Home Manager `programs.git`; `config/shared/.gitconfig` is kept for Windows.
2. **config/unix/** - Unix shell/tool configs plus Linux desktop configs (`.zshrc.base`, `.tmux.conf`, ghostty, hyprland, waybar, fcitx5). Home Manager gates hyprland, waybar, and fcitx5 to Linux.
3. **config/mac/** - macOS-only files used by `dotfile.ps1` or platform-specific Home Manager logic.
4. **config/windows/** - Windows-specific (PowerShell profile, Windows Terminal settings). Used by `dotfile.ps1`.
5. **config/nixos/** - NixOS-only. `configuration.nix` is a tracked full-desktop system config used through the repo flake. Per-machine values (username, hostname, timezone, stateVersion) live in tracked `config/host.nix`; hardware settings live in tracked `config/hardware-configuration.nix`. Edit those files when provisioning a different host. App config files (hyprland, waybar, etc.) and shell/tmux plugin paths are managed by Home Manager from `config/home.nix`. On NixOS the imperative package installers are skipped; packages come from the rebuild.

Files in `config/` subdirectories of each platform layer are linked into `~/.config/` by Home Manager. Top-level dotfiles are linked directly to `$HOME`.

Both loose files and directories under a layer's `config/` are linked into `~/.config/` by their basename (e.g. `config/shared/config/starship.toml` -> `~/.config/starship.toml`, `config/shared/config/nvim/` -> `~/.config/nvim/`).

Home Manager handles individual files in dotfolders we don't want to link wholesale: `config/shared/.ssh/config` -> `~/.ssh/config`, `config/shared/ai/claude/settings.json` -> `~/.claude/settings.json`, tracked Obsidian top-level settings and plugin `data.json` files -> `~/documents/obsidian/Sync/.obsidian/`, and it seeds `~/.codex/config.toml` as a regular writable file because Codex persists preferences there at runtime. On Unix, shared global instructions come from `config/shared/ai/AGENTS.md` and are linked to each agent's native global context path; Windows skips them until FFF is installed there. Agent-agnostic global skills are pinned under `~/.agents/skills/`; Codex discovers that standard location natively and Pi includes it through `settings.json`. Agent-specific plugins, packages, hooks, MCP adapters, memory, models, and UI settings remain native. Only the listed files are linked or seeded - caches, sessions, credentials, `node_modules`, `skills-lock.json`, and plugin runtime artifacts are left alone.

`~/.zshrc` is generated by Home Manager from `config/unix/.zshrc.base`.

## Global Variables

Scripts share state via exported globals: `DRY`, `QUIET`, `FORCE`. These are set by `dotfile` CLI flags and checked throughout all sourced scripts.

## Tests

Tests live under `tests/` with one suite per platform.

```bash
bash tests/bash/runner.sh                  # all bash tests (runs in Docker by default)
bash tests/bash/runner.sh --no-docker      # all bash tests on host (faster while iterating)
bash tests/bash/runner.sh test_packages.sh # single file
pwsh tests/powershell/runner.ps1           # PowerShell tests (Windows / pwsh)
./scripts/check.sh                         # local full check: bash, pwsh if present, Nix flake, ShellCheck via Nix
```

### Bash test pattern

- Default to one `test_<module>.sh` per `scripts/<module>.sh`; split unusually large modules into focused suites. `scripts/packages.sh` uses platform, release pin, Codex runtime, and Neovim suites. Each `test_*` function is auto-discovered by the runner.
- Source `tests/bash/helpers.sh` at the top, then use `setup`/`teardown` to call `init_test_env` / `cleanup_test_env`. Package suites use `setup_packages_test_env`. The helper creates a throwaway `$HOME` under a temp dir and exports `DRY`/`QUIET`/`FORCE`.
- Source the script under test via `source_scripts utils.sh <module>.sh` (always pulls in `platform.sh` automatically).
- Mock OS detection with `mock_uname Linux` / `mock_uname Darwin` (auto-cleared by `cleanup_test_env`).
- Assertions: `assert_equals`, `assert_contains`, `assert_file_exists`, `assert_symlink`, `assert_exit_code`. Failures append to `$ERROR_FILE`; tests do not abort on first failure.
- Default exercise paths: `DRY=true` smoke run, "already installed" short-circuit, `--update` mode does not skip when present, and any platform-specific branches.

### PowerShell test pattern

- One `test_<feature>.ps1` per logical area. Source `tests/powershell/helpers.ps1` and dot-source `dotfile.ps1 -NoMain` to load functions without triggering self-elevation or main dispatch.
- Same dry-run / branch-coverage philosophy as bash tests.

### When adding a new subcommand or script

Add a `tests/bash/test_<name>.sh` (and `tests/powershell/test_<name>.ps1` if Windows-relevant) covering the dry-run path, the skip-if-already-installed path, and any platform branching. Also add a CLI dispatch test in `test_cli.sh` (e.g., `--dry <newcommand>` exits 0 and the help text mentions it).
