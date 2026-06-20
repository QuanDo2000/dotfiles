# Design: Remove oh-my-zsh from dotfiles

**Date:** 2026-06-20
**Status:** Approved

## Goal

Remove oh-my-zsh (omz) from the dotfiles repo and replace it with a minimal,
framework-free zsh setup whose user experience is fast (no perceptible lag at
startup or per-prompt). Priorities, in order:

1. **Minimal** — keep the shell config small and easy to reason about; do not
   add a plugin-management framework.
2. **Fast UX** — no startup lag and no per-prompt lag, even in large git repos.
3. **Consistent, modern prompt across platforms** — the same prompt in zsh and
   PowerShell.

Low dependency count is a nice-to-have, not a driver, so a single fast prompt
binary (starship) shared across platforms is an acceptable trade for goal #3.

Approach chosen: **plain zsh, no plugin framework**, with **starship** as the
prompt (minimal layout, catppuccin palette to match the existing tmux theme).
Plugin loading is plain synchronous `source` of the three standalone plugins —
fast enough at this plugin count, with no framework magic.

## Current state (inventory)

omz touches the following:

- **Install:** `scripts/extras.sh` `install_oh_my_zsh()` (curl unattended
  installer into `~/.oh-my-zsh`); called by `install_extras()`.
- **Core load:** `config/unix/.zshrc` — `export ZSH="$HOME/.oh-my-zsh"`,
  `source "$ZSH/oh-my-zsh.sh"`. compinit is set up by omz here.
- **Config:** `config/unix/.zshrc.base` — `ZSH_THEME="ys"`, a `plugins=(...)`
  array, `ZSH_TMUX_*` settings, `VI_MODE_SET_CURSOR=true`, and
  `zstyle :omz:plugins:alias-finder ...` lines.
- **Plugins (omz built-ins):** `git`, `vi-mode`, `tmux`, `fzf`,
  `alias-finder`, `colored-man-pages`, `zoxide`; plus `brew`, `macos` on macOS
  (`config/mac/.zshrc.mac`: `plugins+=(brew macos)`).
- **Plugins (standalone, already cloned by our own script):**
  `zsh-autosuggestions`, `fast-syntax-highlighting`, `fzf-tab`, currently cloned
  into `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins` by
  `install_zsh_plugins()`.
- **Verify:** `scripts/verify.sh` checks `~/.oh-my-zsh` exists and the three
  plugin dirs exist under `$ZSH_CUSTOM/plugins`.
- **CLI:** `dotfile` `zsh` and `extras` subcommand help text mention oh-my-zsh.
- **Tests:** `tests/bash/test_extras.sh`, `test_verify.sh`, `test_mac_install.sh`
  cover omz install + plugin install + verify; `test_cli.sh` asserts help text.

The three standalone plugins and the tmux plugins (`tmux-yank`, `catppuccin`)
are independent of omz and out of scope except where paths change.

## Replacement mapping

| omz feature | Replacement |
| --- | --- |
| `source $ZSH/oh-my-zsh.sh` | deleted; `.zshrc.base` becomes self-contained |
| compinit (implicit via omz) | explicit cached `compinit` (see below) |
| `zoxide` plugin | `eval "$(zoxide init zsh)"` |
| `fzf` plugin | `source <(fzf --zsh)` (fzf ≥ 0.48) |
| `colored-man-pages` plugin | ~6 `LESS_TERMCAP_*` exports |
| `vi-mode` plugin + `VI_MODE_SET_CURSOR` | `bindkey -v` + `zle-keymap-select` cursor-shape snippet |
| `tmux` plugin + `ZSH_TMUX_*` | inlined autostart snippet |
| `git` plugin | **dropped** (lazygit is used instead) |
| `alias-finder` plugin + its `zstyle` | **dropped** |
| `brew` plugin (mac) | `eval "$(brew shellenv)"` |
| `macos` plugin (mac) | **dropped** |
| `ZSH_THEME="ys"` | **starship** (minimal layout, catppuccin palette) |
| `zsh-autosuggestions` / `fast-syntax-highlighting` / `fzf-tab` | sourced directly from new path |

## Components

### 1. Plugin install location

Move the three standalone plugins from `$ZSH_CUSTOM/plugins` to:

```
${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins
```

This single path is shared between `install_zsh_plugins()` (writer) and
`.zshrc.base` (reader). Define it once in each place via the same expansion.

### 2. `scripts/extras.sh`

- **Delete** `install_oh_my_zsh()`.
- **Repurpose** `install_zsh_plugins()`:
  - target dir = the new XDG path above; `mkdir -p` it.
  - clone the same three repos (unchanged URLs).
  - remove the precondition that `~/.oh-my-zsh` exists.
- **Update** `install_extras()` to drop the `install_oh_my_zsh` call (keep
  `install_zsh_plugins` and `install_tmux_plugins`).

### 3. `config/unix/.zshrc`

- Remove `export ZSH="$HOME/.oh-my-zsh"` and `source "$ZSH/oh-my-zsh.sh"`.
- Keep sourcing `.zshrc.base` and the macOS conditional source of `.zshrc.mac`.
- compinit moves into `.zshrc.base` (so the jj-completion comment moves with it).

### 4. `config/unix/.zshrc.base` (core rewrite)

Self-contained, ordered:

1. **Cached compinit:**
   ```zsh
   autoload -Uz compinit
   _zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
   if [[ -n "$_zcompdump"(#qN.mh+24) ]]; then
     compinit -d "$_zcompdump"
   else
     compinit -C -d "$_zcompdump"
   fi
   ```
   (rebuild dump if older than 24h, otherwise skip the security check for speed).
2. **Native one-liners:** zoxide init, `fzf --zsh`, `colored-man-pages`
   `LESS_TERMCAP_*` exports.
3. **vi-mode:** `bindkey -v`, reduced `KEYTIMEOUT`, and a `zle-keymap-select` +
   `zle-line-init` block that sets a block cursor in normal mode and a beam in
   insert mode (replicating `VI_MODE_SET_CURSOR=true`).
4. **tmux autostart:** inlined snippet replicating the prior settings —
   autostart once, attach to (or create) session `main`, do **not** quit the
   shell when tmux exits (`AUTOQUIT=false`). Guard against running inside an
   existing `$TMUX`, non-interactive shells, and known nested contexts
   (e.g. VS Code) so it does not loop.
5. **Source standalone plugins** in this order (order matters):
   `fzf-tab` (after compinit) → `zsh-autosuggestions` →
   `fast-syntax-highlighting` (must be sourced last).
6. **Prompt:** `eval "$(starship init zsh)"` (last, after plugins).
7. **Removed:** `ZSH_THEME`, the `plugins=(...)` array, all `ZSH_TMUX_*`,
   `VI_MODE_SET_CURSOR`, and the `zstyle :omz:plugins:alias-finder` lines.

### 5. starship prompt config (cross-platform)

- New file `config/shared/starship.toml`, symlinked to
  `~/.config/starship.toml` (shared layer, so zsh and PowerShell read the same
  config). Add the carveout in `setup_symlinks` if a shared `config/` file does
  not already land in `~/.config` automatically.
- Layout: starship's **minimal** module set (directory, git branch, git status,
  character/exit-status) — no heavy/slow modules — to keep it fast and clean.
- Colors: define and apply the **catppuccin** palette (mocha, to match the tmux
  catppuccin theme) via starship's `palette` mechanism.
- Per-prompt speed: rely on starship's built-in module timeouts; do not enable
  expensive modules (e.g. per-language version detection) that could lag in
  large repos.

### 6. starship install

- **`scripts/packages.sh`** — add `starship` to the apt/pacman/brew install
  paths. Where a distro package is unavailable or too old, fall back to the
  official installer script. Follow the existing per-OS package patterns.
- **`dotfile.ps1` (Windows)** — install starship via the existing Windows
  package mechanism (winget/scoop) alongside the other packages.

### 7. PowerShell profile

- Add `Invoke-Expression (&starship init powershell)` to the PowerShell profile
  in `config/windows/`, so Windows uses the same `~/.config/starship.toml`.

### 8. `config/mac/.zshrc.mac`

- Remove `plugins+=(brew macos)`.
- Ensure brew is on PATH via `eval "$(brew shellenv)"` (only if not already
  established elsewhere in the mac shell init). Drop the `macos` plugin
  (its aliases are not relied upon).

### 9. `scripts/verify.sh`

- Remove the `~/.oh-my-zsh` existence check.
- Point the three plugin-dir checks at the new XDG path.
- Add a check that `starship` is on PATH.

### 10. `dotfile` CLI

- Update `zsh` and `extras` subcommand help text to drop "oh-my-zsh"
  (e.g. `zsh` → "Install zsh plugins"; `extras` → "Install zsh plugins,
  tmux plugins").
- The `zsh` subcommand dispatch drops `install_oh_my_zsh`, keeps
  `install_zsh_plugins`.

### 11. Tests

- `test_extras.sh`: remove `install_oh_my_zsh` tests; update
  `install_zsh_plugins` tests to the new path and drop the
  "fails when omz missing" case (replace with a "creates target dir" case).
- `test_verify.sh`: drop omz-detection tests; update plugin-detection path;
  add a starship-on-PATH detection test.
- `test_mac_install.sh`: remove omz-install tests; update plugin tests/path;
  keep `install_extras` dry-run coverage minus omz.
- `test_packages.sh`: assert starship is included in the package install path
  (dry-run) for each OS branch.
- `test_cli.sh`: update the help-text assertions for `zsh`/`extras`.
- PowerShell (`tests/powershell/`): if Windows package install / profile is
  covered, add starship to the relevant dry-run assertion.

## Considered alternatives (rejected)

- **zinit (or another plugin manager).** Most capable manager; turbo mode defers
  plugin loading for the fastest *perceived* startup. Rejected: it is the
  heaviest, most "magic" option, contradicts the "minimal" goal, and turbo's
  benefit is marginal with only three plugins (synchronous sourcing is already
  fast, and deferred loading is replicable in ~10 lines if ever needed).
- **Hand-rolled `ys` prompt via `vcs_info`.** Zero dependencies, preserves the
  exact current look. Rejected once cross-platform prompt consistency became a
  goal: it only covers the unix zsh layers (Windows would drift), and a
  `vcs_info`-based prompt is the more likely source of lag in large repos.
- **starship with a full preset (e.g. catppuccin-powerline).** Rejected in favor
  of the minimal layout for speed and visual simplicity; only the catppuccin
  *palette* is adopted, not a heavy multi-segment layout.

## Out of scope

- tmux plugins (`tmux-yank`, `catppuccin`) — unchanged.
- Language toolchain, package manager core, and symlink logic — unchanged
  (`.zshrc.base` is still symlinked the same way; only a starship.toml carveout
  is added if needed).

## Migration / cleanup note

After this lands, `~/.oh-my-zsh` is no longer used but is not auto-deleted by
the scripts (the installer never removed user files). Removing it on existing
machines is a manual `rm -rf ~/.oh-my-zsh`, then re-running `dotfile zsh`
(repopulates the new plugin path) and `dotfile packages` (installs starship).
This will be called out in the implementation plan rather than automated, to
avoid deleting user data.

## Risks

- **starship availability/version across platforms.** The apt/pacman/brew/winget
  package may be missing or stale on some targets; the install step needs a
  reliable fallback (official installer) so a fresh machine always gets it.
- **Shared starship.toml symlink.** Must confirm the shared-layer config file
  actually lands at `~/.config/starship.toml` on both unix and Windows.
- **Plugin load order:** `fast-syntax-highlighting` must be last or highlighting
  breaks; `fzf-tab` must follow `compinit`.
- **tmux autostart loops:** the guard conditions must prevent re-entrancy inside
  an existing tmux session.
