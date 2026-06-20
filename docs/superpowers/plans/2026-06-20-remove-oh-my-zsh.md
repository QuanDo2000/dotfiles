# Remove oh-my-zsh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove oh-my-zsh from the dotfiles and replace it with a framework-free zsh setup using direct plugin sourcing plus starship as a shared, cross-platform prompt.

**Architecture:** zsh stops loading the oh-my-zsh framework. The three standalone plugins (`zsh-autosuggestions`, `fast-syntax-highlighting`, `fzf-tab`) move to an XDG path and are sourced directly from `.zshrc.base`, which also inlines native replacements (compinit, zoxide, fzf, vi-mode, colored-man-pages, tmux autostart). The omz `ys` theme and the Windows oh-my-posh `ys` theme are both replaced by starship reading one shared `~/.config/starship.toml` (minimal layout, catppuccin-mocha palette).

**Tech Stack:** bash (installer scripts + tests), zsh (shell config), PowerShell (Windows installer + profile), starship (prompt), TOML (starship config).

## Global Constraints

- **Plugin path:** the standalone zsh plugins live at `${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins`. The installer (writer) and `.zshrc.base` (reader) and `verify.sh` (checker) must all use this exact expansion.
- **starship config path:** one shared file `config/shared/starship.toml`, symlinked to `~/.config/starship.toml` on every platform (Unix, macOS, Windows).
- **fzf version floor:** `fzf --zsh` requires fzf ≥ 0.48 (already the case via the package managers).
- **Plugin load order (mandatory):** `compinit` → `fzf-tab` → `zsh-autosuggestions` → `fast-syntax-highlighting` (last). starship init runs after all plugins.
- **Commits are GPG-signed.** `git commit` needs a TTY for the passphrase and will fail in a non-interactive agent. At execution time, either the human runs each commit (`! git commit -S ...`), or — only if the user approves — use `git -c commit.gpgsign=false commit`. Decide this once before starting and apply to every commit step below.
- **Test runner:** `bash tests/bash/runner.sh --no-docker` runs the full bash suite on the host (faster while iterating); `bash tests/bash/runner.sh test_<file>.sh` runs one file. Windows tests: `pwsh tests/powershell/runner.ps1` (only runnable on a pwsh host).

---

### Task 1: Move zsh plugins off oh-my-zsh in `scripts/extras.sh`

**Files:**
- Modify: `scripts/extras.sh:4-14` (delete `install_oh_my_zsh`), `scripts/extras.sh:40-58` (`install_zsh_plugins`), `scripts/extras.sh:77-83` (`install_extras`)
- Test: `tests/bash/test_extras.sh`, `tests/bash/test_mac_install.sh`

**Interfaces:**
- Consumes: `clone_if_missing <name> <repo> <dest>` (unchanged, `scripts/extras.sh:18-38`), globals `DRY`, `info/success/fail` from `utils.sh`.
- Produces: `install_zsh_plugins` clones into `${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins`; `install_oh_my_zsh` no longer exists; `install_extras` calls only `install_zsh_plugins` + `install_tmux_plugins`.

- [ ] **Step 1: Update `test_extras.sh` to the new behavior (failing first)**

In `tests/bash/test_extras.sh`, delete the two oh-my-zsh tests (lines 31-50, the `install_oh_my_zsh` block) and replace the `install_zsh_plugins` block (lines 122-174) with the version below. The new tests target the XDG path and drop the "fails without oh-my-zsh" expectation:

```bash
# ---------------------------------------------------------------------------
# install_zsh_plugins
# ---------------------------------------------------------------------------

test_install_zsh_plugins_dry_run() {
  DRY=true
  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Installing zsh plugins"
}

test_install_zsh_plugins_creates_target_dir() {
  mock_cmd git 'mkdir -p "$3/.git"; exit 0'

  (install_zsh_plugins 2>&1) >/dev/null

  assert_file_exists "$HOME/.local/share/zsh/plugins/zsh-autosuggestions/.git"
}

test_install_zsh_plugins_git_clone_failure() {
  # Simulate a flaky network: mock git so `git clone` always exits non-zero.
  mock_cmd git 'echo "mock git: $*" >&2; exit 42'

  local exit_code=0
  (install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_zsh_plugins should propagate git clone failure" >> "$ERROR_FILE"
  fi
}

test_install_zsh_plugins_all_already_installed() {
  # With every plugin dir present (with .git inside, marking a complete
  # clone), git should never be invoked — mock git as a canary that fails
  # if called so we notice unwanted re-clones.
  local plugins_dir="$HOME/.local/share/zsh/plugins"
  mkdir -p "$plugins_dir/zsh-autosuggestions/.git" \
    "$plugins_dir/fast-syntax-highlighting/.git" \
    "$plugins_dir/fzf-tab/.git"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_zsh_plugins should not re-clone existing plugins ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing zsh plugins"
}
```

- [ ] **Step 2: Run the extras tests to confirm they fail**

Run: `bash tests/bash/runner.sh --no-docker test_extras.sh`
Expected: FAIL — `install_oh_my_zsh` references are gone but `install_zsh_plugins` still writes to the old `~/.oh-my-zsh/custom` path and still hard-fails when `~/.oh-my-zsh` is missing, so `test_install_zsh_plugins_creates_target_dir` and `test_install_zsh_plugins_all_already_installed` fail.

- [ ] **Step 3: Rewrite the functions in `scripts/extras.sh`**

Delete lines 4-14 (`install_oh_my_zsh`). Replace `install_zsh_plugins` (lines 40-58) with:

```bash
function install_zsh_plugins {
  info "Installing zsh plugins..."
  if [[ "$DRY" == "false" ]]; then
    local plugins_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
    mkdir -p "$plugins_dir" || fail "Failed to create $plugins_dir"
    clone_if_missing "zsh-autosuggestions" \
      "https://github.com/zsh-users/zsh-autosuggestions" \
      "$plugins_dir/zsh-autosuggestions"
    clone_if_missing "fast-syntax-highlighting" \
      "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" \
      "$plugins_dir/fast-syntax-highlighting"
    clone_if_missing "fzf-tab" \
      "https://github.com/Aloxaf/fzf-tab" \
      "$plugins_dir/fzf-tab"
  fi
  success "Finished installing zsh plugins"
}
```

In `install_extras` (now near line 65), delete the `install_oh_my_zsh` line so the body is:

```bash
function install_extras {
  info "Installing extras"
  install_zsh_plugins
  install_tmux_plugins
  success "Finished installing extras"
}
```

- [ ] **Step 4: Update `test_mac_install.sh` (it also exercises extras.sh)**

In `tests/bash/test_mac_install.sh`:
- Delete `test_install_oh_my_zsh_dry_run` (lines 88-94) and `test_install_oh_my_zsh_already_installed` (lines 96-104).
- Delete `test_install_zsh_plugins_fails_without_omz` (lines 127-137).
- Replace the body of `test_install_zsh_plugins_already_installed` (lines 114-125) so it uses the XDG path:

```bash
test_install_zsh_plugins_already_installed() {
  DRY=false
  local plugins_dir="$HOME/.local/share/zsh/plugins"
  mkdir -p "$plugins_dir/zsh-autosuggestions/.git"
  mkdir -p "$plugins_dir/fast-syntax-highlighting/.git"
  mkdir -p "$plugins_dir/fzf-tab/.git"

  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Finished installing zsh plugins"
}
```

- In `test_install_extras_dry_run` (lines 159-167), remove the `assert_contains "$output" "Installing oh-my-zsh"` line.
- In `test_setup_dotfiles_dry_run_mac` (lines 173-201), replace `assert_contains "$output" "Installing oh-my-zsh"` (line 198) with `assert_contains "$output" "Installing zsh plugins"`.
- In `test_dotfile_extras_command_dry` (lines 214-221), remove the `assert_contains "$output" "Installing oh-my-zsh"` line (line 218).

- [ ] **Step 5: Run both test files to confirm they pass**

Run: `bash tests/bash/runner.sh --no-docker test_extras.sh && bash tests/bash/runner.sh --no-docker test_mac_install.sh`
Expected: PASS (all green).

- [ ] **Step 6: Commit**

```bash
git add scripts/extras.sh tests/bash/test_extras.sh tests/bash/test_mac_install.sh
git commit -S -m "Move zsh plugins to XDG path, drop oh-my-zsh install"
```

---

### Task 2: Remove oh-my-zsh from the `dotfile` CLI

**Files:**
- Modify: `dotfile:76-77` (usage text), `dotfile:130-133` (`zsh` dispatch)
- Test: `tests/bash/test_cli.sh`

**Interfaces:**
- Consumes: `install_zsh_plugins`, `install_extras` (from Task 1).
- Produces: `zsh` subcommand runs only `install_zsh_plugins`; help text no longer mentions oh-my-zsh.

- [ ] **Step 1: Add a failing help-text test**

Append to `tests/bash/test_cli.sh`:

```bash
test_help_no_oh_my_zsh() {
  local output
  output=$(bash "$DOTFILE_CMD" --help 2>&1)
  if [[ "$output" == *"oh-my-zsh"* ]]; then
    echo "  FAILED: help text should no longer mention oh-my-zsh" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "zsh plugins"
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/bash/runner.sh --no-docker test_cli.sh`
Expected: FAIL — help still contains "oh-my-zsh".

- [ ] **Step 3: Update the CLI**

In `dotfile`, change the two usage lines (76-77) from:

```
  extras      Install oh-my-zsh, zsh plugins, tmux plugins
  zsh         Install oh-my-zsh and zsh plugins
```

to:

```
  extras      Install zsh plugins, tmux plugins
  zsh         Install zsh plugins
```

Change the `zsh` dispatch (lines 130-133) from:

```bash
zsh)
  install_oh_my_zsh
  install_zsh_plugins
  ;;
```

to:

```bash
zsh)
  install_zsh_plugins
  ;;
```

- [ ] **Step 4: Run the CLI tests to confirm they pass**

Run: `bash tests/bash/runner.sh --no-docker test_cli.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dotfile tests/bash/test_cli.sh
git commit -S -m "Drop oh-my-zsh from dotfile CLI help and zsh subcommand"
```

---

### Task 3: Update `scripts/verify.sh` (plugin path, starship, drop omz)

**Files:**
- Modify: `scripts/verify.sh:8` (REQUIRED_TOOLS), `scripts/verify.sh:68-75` (omz + plugin checks)
- Test: `tests/bash/test_verify.sh`

**Interfaces:**
- Consumes: `_check_tool`, `_check_dir` (unchanged).
- Produces: verify checks `starship` on PATH and the three plugins under the XDG path; no oh-my-zsh check.

- [ ] **Step 1: Update `test_verify.sh` (failing first)**

In `tests/bash/test_verify.sh`:
- Delete `test_verify_oh_my_zsh_detected` (lines 67-73) and `test_verify_oh_my_zsh_missing` (lines 75-81).
- Replace `test_verify_zsh_plugin_detected` (lines 83-89) with:

```bash
test_verify_zsh_plugin_detected() {
  mkdir -p "$DOTFILES_DIR"
  mkdir -p "$HOME/.local/share/zsh/plugins/zsh-autosuggestions"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "zsh plugin: zsh-autosuggestions"
}

test_verify_starship_checked() {
  mkdir -p "$DOTFILES_DIR"
  local output
  output=$(verify 2>&1) || true
  # starship is in REQUIRED_TOOLS, so verify reports it either way.
  if [[ "$output" != *"starship"* ]]; then
    echo "  FAILED: verify should check for starship" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/bash/runner.sh --no-docker test_verify.sh`
Expected: FAIL — verify still checks `~/.oh-my-zsh` and the old plugin path; `starship` not yet in REQUIRED_TOOLS.

- [ ] **Step 3: Edit `scripts/verify.sh`**

Add `starship` to `REQUIRED_TOOLS` (line 8):

```bash
REQUIRED_TOOLS=(git zsh nvim tmux fzf fd rg lazygit zoxide starship)
```

Replace the oh-my-zsh + plugin verification block (lines 68-75) with:

```bash
  info "Verifying zsh plugins..."
  local plugins_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
  for plugin in zsh-autosuggestions fast-syntax-highlighting fzf-tab; do
    _check_dir "$plugins_dir/$plugin" "zsh plugin: $plugin" "zsh plugin missing: $plugin"
  done
```

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/bash/runner.sh --no-docker test_verify.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify.sh tests/bash/test_verify.sh
git commit -S -m "verify: check starship and XDG plugin path, drop oh-my-zsh"
```

---

### Task 4: Install starship in `scripts/packages.sh`

**Files:**
- Modify: `scripts/packages.sh` — `ARCH_PACKAGES` (461-466), `MAC_BREW_PACKAGES` (494-497), add `setup_starship`, call it in `install_debian` (443-459) and `update_debian` (428-441)
- Test: `tests/bash/test_packages.sh`

**Interfaces:**
- Consumes: `_action_verb`, `info/success/fail`, `DRY`.
- Produces: `setup_starship [--update]`; `starship` present in `ARCH_PACKAGES` and `MAC_BREW_PACKAGES`.

- [ ] **Step 1: Add failing tests to `test_packages.sh`**

Append to `tests/bash/test_packages.sh`:

```bash
# ---------------------------------------------------------------------------
# setup_starship + package lists
# ---------------------------------------------------------------------------

test_setup_starship_dry_run() {
  DRY=true
  local output
  output=$(setup_starship 2>&1)

  assert_contains "$output" "starship"
  assert_contains "$output" "Finished starship"
}

test_setup_starship_already_installed() {
  DRY=false
  echo '#!/bin/bash' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_starship 2>&1)

  assert_contains "$output" "Already installed starship"
}

test_setup_starship_update_does_not_skip() {
  DRY=true
  echo '#!/bin/bash' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(setup_starship --update 2>&1)

  if [[ "$output" == *"Already installed"* ]]; then
    echo "  FAILED: --update should not skip when already installed" >> "$ERROR_FILE"
  fi
}

test_arch_packages_include_starship() {
  assert_contains "${ARCH_PACKAGES[*]}" "starship"
}

test_mac_packages_include_starship() {
  assert_contains "${MAC_BREW_PACKAGES[*]}" "starship"
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: FAIL — `setup_starship` undefined; arrays lack `starship`.

- [ ] **Step 3: Implement in `scripts/packages.sh`**

Add `starship` to `ARCH_PACKAGES` (e.g. on the line with `zoxide`) and to `MAC_BREW_PACKAGES` (e.g. after `zoxide jj`). For Debian (apt's starship is unreliable), add this function next to `setup_lazygit` (after line 307):

```bash
# Install or update the starship prompt. Arch installs it via pacman and macOS
# via brew (see ARCH_PACKAGES / MAC_BREW_PACKAGES); Debian apt does not reliably
# ship starship, so install it via the official script into ~/.local/bin.
# Idempotent: in install mode, no-op if `starship` is already on PATH; --update
# always reinstalls the latest. Usage: setup_starship [--update]
function setup_starship {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "$(_action_verb "$update") starship..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v starship >/dev/null 2>&1; then
      info "Already installed starship"
      success "Finished starship"
      return
    fi
    mkdir -p "$HOME/.local/bin"
    curl -sS https://starship.rs/install.sh \
      | sh -s -- -y -b "$HOME/.local/bin" \
      || fail "Failed to install starship"
  fi
  success "Finished starship"
}
```

In `install_debian` (after `setup_lazygit`, line 453), add `setup_starship`. In `update_debian` (after `setup_neovim --update`, line 434), add `setup_starship --update`.

- [ ] **Step 4: Run to confirm pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh
git commit -S -m "Install starship across apt/pacman/brew"
```

---

### Task 5: Add the shared `starship.toml` and symlink it (Unix)

**Files:**
- Create: `config/shared/starship.toml`
- Modify: `scripts/symlinks.sh:120-178` (`setup_symlinks` — add a carveout)

**Interfaces:**
- Consumes: `link_files`, globals `DRY`, `DOTFILES_DIR`.
- Produces: `~/.config/starship.toml` symlink on Unix/macOS.

- [ ] **Step 1: Create `config/shared/starship.toml`**

Minimal layout, catppuccin-mocha palette:

```toml
"$schema" = 'https://starship.rs/config-schema.json'

format = """
$directory\
$git_branch\
$git_status\
$character"""

add_newline = true
palette = "catppuccin_mocha"

[directory]
style = "blue"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "mauve"

[git_status]
style = "red"

[character]
success_symbol = "[\\$](green)"
error_symbol = "[\\$](red)"
vimcmd_symbol = "[<](green)"

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
mauve = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"
```

- [ ] **Step 2: Add the symlink carveout in `scripts/symlinks.sh`**

`setup_symlinks_folder` only links *directories* under `config/`, not loose files, so a top-level `starship.toml` needs an explicit carveout. Inside `setup_symlinks`, after the OpenCode block (after line 170, before the `dotfile` entry-point block at line 172), add:

```bash
  # starship prompt config — shared across zsh and PowerShell. Lives at
  # config/shared/starship.toml but must land at ~/.config/starship.toml
  # (setup_symlinks_folder only links directories under config/, not loose files).
  local starship_src="$DOTFILES_DIR/config/shared/starship.toml"
  if [[ -f "$starship_src" ]]; then
    if [[ "$DRY" != "true" ]]; then
      mkdir -p "$HOME/.config" || fail "Failed to create $HOME/.config"
    fi
    link_files "$starship_src" "$HOME/.config/starship.toml"
  fi
```

- [ ] **Step 3: Verify the symlink is created in a dry run and a real run**

Run (dry, should log the link without creating it):
`bash tests/bash/runner.sh --no-docker test_cli.sh`
Expected: PASS (the `--dry symlinks`/`--dry all` paths still exit 0).

Then a real local link check (safe — links into your actual `~/.config`):
`./dotfile symlinks` then `readlink ~/.config/starship.toml`
Expected: prints a path ending in `dotfiles/config/shared/starship.toml`.

- [ ] **Step 4: Commit**

```bash
git add config/shared/starship.toml scripts/symlinks.sh
git commit -S -m "Add shared starship.toml and symlink it on Unix"
```

---

### Task 6: Rewrite the zsh config (`.zshrc`, `.zshrc.base`, `.zshrc.mac`)

**Files:**
- Modify: `config/unix/.zshrc`, `config/unix/.zshrc.base`, `config/mac/.zshrc.mac`

**Interfaces:**
- Consumes: plugins at `${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins` (Task 1), `starship` on PATH (Task 4), `~/.config/starship.toml` (Task 5).
- Produces: a self-contained zsh setup with no oh-my-zsh.

This task is verified by launching a real zsh and observing behavior (no unit tests cover live shell config).

- [ ] **Step 1: Rewrite `config/unix/.zshrc.base`**

Replace the entire file with:

```zsh
# Base config (tracked in dotfiles repo). Sourced first by ~/.zshrc.

# Environment variables
export SHELL=$(which zsh)
export EDITOR=nvim
export GPG_TTY=$(tty)

# vim is no longer installed locally (neovim is the editor); keep muscle memory.
alias vim=nvim

# Hyprshot
[ ! -d "$HOME/hyprshot" ] && mkdir -p "$HOME/hyprshot"
export HYPRSHOT_DIR="$HOME/hyprshot"

# Path
[ -d "/opt/nvim-linux-x86_64/bin" ] && export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "/snap/bin" ] && export PATH="/snap/bin:$PATH"
[ -d "$HOME/.devcontainers/bin" ] && export PATH="$HOME/.devcontainers/bin:$PATH"

# macOS-specific config (brew shellenv, etc.) — must run before tools below so
# brew-installed binaries (starship, zoxide, fzf) are on PATH.
[ -e "$HOME/.zshrc.mac" ] && source "$HOME/.zshrc.mac"

# tmux autostart: on an interactive shell not already inside tmux, attach to
# (or create) the "main" session. Replaces the omz tmux plugin. Not exec'd, so
# exiting tmux drops back to this shell (old ZSH_TMUX_AUTOQUIT=false). Guards
# avoid nested tmux and embedded shells (VS Code, Emacs, Vim).
if [[ -z "$TMUX" && -o interactive && -z "$ZSH_TMUX_STARTED" \
      && "$TERM_PROGRAM" != "vscode" && -z "$INSIDE_EMACS" && -z "$VIMRUNTIME" ]] \
   && command -v tmux >/dev/null 2>&1; then
  export ZSH_TMUX_STARTED=1
  tmux attach -t main 2>/dev/null || tmux new -s main
fi

# Completion system (cached for fast startup). Rebuild + security-check the dump
# only when it is older than 24h; otherwise load it fast (-C skips the check).
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zcompdump:h}"
if [[ -n "$_zcompdump"(#qN.mh+24) ]]; then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi

# vi mode (replaces the omz vi-mode plugin + VI_MODE_SET_CURSOR=true)
bindkey -v
export KEYTIMEOUT=1
_set_cursor_shape() {
  case "$KEYMAP" in
    vicmd|visual) printf '\e[2 q' ;;  # block cursor in normal mode
    *)            printf '\e[6 q' ;;  # beam cursor in insert mode
  esac
}
zle-keymap-select() { _set_cursor_shape }
zle-line-init() { _set_cursor_shape }
zle -N zle-keymap-select
zle -N zle-line-init

# colored man pages (replaces the omz colored-man-pages plugin)
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

# zoxide — bind it to `cd` (replaces the omz zoxide plugin + ZOXIDE_CMD_OVERRIDE)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --cmd cd)"

# fzf key bindings + fuzzy completion (replaces the omz fzf plugin; needs fzf >= 0.48)
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)

# Standalone plugins — sourced directly, order matters:
# fzf-tab (after compinit) -> autosuggestions -> fast-syntax-highlighting (last).
_zsh_plugins="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
[ -f "$_zsh_plugins/fzf-tab/fzf-tab.plugin.zsh" ] \
  && source "$_zsh_plugins/fzf-tab/fzf-tab.plugin.zsh"
[ -f "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] \
  && source "$_zsh_plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -f "$_zsh_plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ] \
  && source "$_zsh_plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"

# Prompt (replaces the omz "ys" theme). Reads ~/.config/starship.toml.
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
```

- [ ] **Step 2: Rewrite `config/unix/.zshrc`**

Remove the `ZSH` export and the `source "$ZSH/oh-my-zsh.sh"` line. The file becomes (compinit now runs inside `.zshrc.base`, so the jj note is updated):

```zsh
# Base config (tracked in dotfiles repo)
[ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"

# jj (jujutsu) completion — dynamic mode, requires compinit (set up in .zshrc.base).
command -v jj >/dev/null 2>&1 && source <(COMPLETE=zsh jj)

# Go
export GOPATH="$HOME/.local/go"
if [[ -e "$GOPATH" ]]; then
  export GOBIN=$GOPATH/bin
  export PATH=$PATH:$GOBIN
fi

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# bun
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
```

- [ ] **Step 3: Rewrite `config/mac/.zshrc.mac`**

Replace the single `plugins+=(brew macos)` line with brew env setup:

```zsh
# Homebrew environment (PATH, etc.) — replaces the omz brew plugin.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

- [ ] **Step 4: Re-link and launch a fresh zsh to verify**

Run: `./dotfile symlinks` (re-links the updated `.zshrc*`), then `./dotfile zsh` (clones the plugins to the XDG path if not present), then start a new interactive shell: `zsh -i -c 'echo OK; print -r -- $KEYMAP'`.
Expected: starts with no oh-my-zsh errors, prints `OK`. In an interactive terminal, confirm: starship prompt renders, `cd` uses zoxide, syntax highlighting + autosuggestions work, `Esc` switches the cursor to a block (vi normal mode), and `fzf` keybindings (Ctrl-R, Ctrl-T) work.

- [ ] **Step 5: Commit**

```bash
git add config/unix/.zshrc config/unix/.zshrc.base config/mac/.zshrc.mac
git commit -S -m "Rewrite zsh config without oh-my-zsh; use starship prompt"
```

---

### Task 7: Switch Windows from oh-my-posh to starship

**Files:**
- Modify: `dotfile.ps1:195-200` (winget package list), `dotfile.ps1:566-634` (`SetupSymlinks` — add starship.toml link), `config/windows/Powershell/Microsoft.PowerShell_profile.ps1:1`

**Interfaces:**
- Consumes: `LinkFile`, `$userHome`, shared `starship.toml` (Task 5).
- Produces: starship installed via winget, profile inits starship, `~/.config/starship.toml` linked on Windows.

This task is verified on a Windows/pwsh host; the PowerShell test suite has no assertions on winget package contents or specific symlink targets, so it stays green.

- [ ] **Step 1: Replace oh-my-posh with starship in the winget list**

In `dotfile.ps1`, change the package array (lines 195-200) so `"JanDeDobbeleer.OhMyPosh"` becomes `"Starship.Starship"`:

```powershell
    $wingetPkgs = @(
        "Microsoft.Powershell", "Git.Git", "Microsoft.WindowsTerminal",
        "Starship.Starship", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd", "JernejSimoncic.Wget",
        "junegunn.fzf", "Schniz.fnm", "jj-vcs.jj"
    )
```

- [ ] **Step 2: Update the PowerShell profile prompt init**

In `config/windows/Powershell/Microsoft.PowerShell_profile.ps1`, replace line 1:

```powershell
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH/ys.omp.json" | Invoke-Expression
```

with:

```powershell
Invoke-Expression (&starship init powershell)
```

- [ ] **Step 3: Link the shared starship.toml on Windows**

In `dotfile.ps1` `SetupSymlinks`, after the Jujutsu config block (after line 620, before the dotfile.ps1 entry-point block at line 622), add:

```powershell
    # starship prompt config — shared with zsh, read from ~/.config/starship.toml.
    $starshipConfigDir = "$userHome\.config"
    if (-not (Test-Path $starshipConfigDir)) {
        New-Item -ItemType Directory -Path $starshipConfigDir | Out-Null
    }
    LinkFile -source (Join-Path $sharedPath "starship.toml") -destination (Join-Path $starshipConfigDir "starship.toml")
```

- [ ] **Step 4: Verify on a pwsh host (if available)**

Run: `pwsh tests/powershell/runner.ps1`
Expected: PASS (existing tests unaffected). On a real Windows machine, run `dotfile.ps1 symlinks` and open a new pwsh session — the starship prompt should render using the shared config.

- [ ] **Step 5: Commit**

```bash
git add dotfile.ps1 config/windows/Powershell/Microsoft.PowerShell_profile.ps1
git commit -S -m "Windows: replace oh-my-posh with starship"
```

---

### Task 8: Docs sweep + full test run + migration note

**Files:**
- Modify: `CLAUDE.md` (the `extras.sh` description and any oh-my-zsh mentions), `README*` if present
- Reference: the spec's migration note

- [ ] **Step 1: Find every remaining oh-my-zsh / oh-my-posh reference**

Run: `grep -rni "oh-my-zsh\|oh-my-posh\|ZSH_CUSTOM\|\.oh-my-zsh" --include='*.md' --include='*.sh' --include='*.ps1' --include='*.zsh*' . | grep -v docs/superpowers`
Expected: only documentation hits remain (all code hits were handled in Tasks 1-7). If any code hit remains, fix it in the owning task's file.

- [ ] **Step 2: Update `CLAUDE.md`**

In `CLAUDE.md`, update the `extras.sh` bullet under "Architecture" to drop oh-my-zsh, e.g. change "oh-my-zsh, zsh plugins, and the directly-cloned tmux plugins" to "zsh plugins (cloned to `~/.local/share/zsh/plugins`) and the directly-cloned tmux plugins; the prompt is starship (config at `config/shared/starship.toml`)". Update the `dotfile extras` / Key Commands descriptions that mention oh-my-zsh. Add a one-line note that the shared `starship.toml` is symlinked to `~/.config/starship.toml` on all platforms.

- [ ] **Step 3: Add the migration note for existing machines**

Append a short "Migrating off oh-my-zsh" subsection to `CLAUDE.md` (or `README` if that's where install docs live):

```markdown
### Migrating an existing machine off oh-my-zsh

oh-my-zsh is no longer used. On a machine provisioned before this change:

1. `dotfile packages`  # installs starship
2. `dotfile zsh`       # clones plugins to ~/.local/share/zsh/plugins
3. `dotfile symlinks`  # links ~/.config/starship.toml and the new .zshrc files
4. `rm -rf ~/.oh-my-zsh`  # optional: remove the now-unused framework

On Windows, `oh-my-posh` can likewise be uninstalled: `winget uninstall JanDeDobbeleer.OhMyPosh`.
```

- [ ] **Step 4: Run the entire bash test suite**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: all suites PASS.

- [ ] **Step 5: Run the full suite in Docker (matches CI)**

Run: `bash tests/bash/runner.sh`
Expected: all suites PASS.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -S -m "Docs: remove oh-my-zsh, document starship + migration"
```

---

## Self-Review

**Spec coverage:**
- Plugin path (XDG) → Task 1 (write), Task 3 (verify), Task 6 (read). ✔
- extras.sh delete omz / repurpose plugins → Task 1. ✔
- `.zshrc` / `.zshrc.base` rewrite (compinit, zoxide, fzf, colored-man, vi-mode, tmux, plugin order, starship) → Task 6. ✔
- Drop git/alias-finder plugins + omz zstyle → Task 6 (omitted from rewrite). ✔
- `.zshrc.mac` brew shellenv, drop brew/macos plugins → Task 6. ✔
- starship config (minimal + catppuccin) cross-platform → Task 5. ✔
- starship install (apt/pacman/brew + winget) → Task 4 (Unix), Task 7 (Windows). ✔
- PowerShell init → Task 7. ✔
- verify.sh → Task 3. ✔
- CLI help → Task 2. ✔
- Tests (extras/verify/mac/packages/cli) → Tasks 1-4. ✔
- Migration note → Task 8. ✔
- Considered alternatives (zinit, hand-rolled ys, starship presets) → documented in spec; no implementation. ✔

**Bonus beyond spec:** the spec didn't note Windows already used oh-my-posh; Task 7 removes it (replacing, not stacking, the prompt) to truly unify — consistent with the cross-platform goal.

**Placeholder scan:** no TBD/TODO; every code step shows full content. ✔

**Type/name consistency:** plugin path expansion `${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins` identical in Tasks 1/3/6; `setup_starship` signature matches its tests; `install_zsh_plugins`/`install_extras` names consistent across CLI + tests. ✔
