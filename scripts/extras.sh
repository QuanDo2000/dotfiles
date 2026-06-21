#!/bin/bash
set -eo pipefail

# Clone a git repo into $dest if $dest doesn't already exist.
# Usage: clone_if_missing <name> <repo-url> <dest> [git-args...]
function clone_if_missing {
  local name="$1" repo="$2" dest="$3"
  shift 3
  info "Installing $name..."
  # If dest exists without .git inside, it's a leftover partial clone from
  # a prior failure — wipe so the next branch can re-clone cleanly.
  if [[ -d "$dest" && ! -d "$dest/.git" ]]; then
    info "Found partial $name install at $dest; removing"
    rm -rf "$dest"
  fi
  if [ ! -d "$dest" ]; then
    if [[ "$DRY" == "true" ]]; then
      info "Would clone $repo into $dest"
    else
      # On clone failure, remove the (possibly partial) dest so the next
      # run doesn't think it's already installed.
      git clone "$@" "$repo" "$dest" || { rm -rf "$dest"; fail "Failed to clone $name"; }
    fi
  fi
  success "Finished installing $name"
}

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

function install_tmux_plugins {
  info "Installing tmux plugins..."
  # No plugin manager: tmux-sensible and tmux-pain-control are inlined in
  # .tmux.conf, so we only clone the two plugins that ship runnable scripts
  # (tmux-yank, catppuccin) and `run` them directly from .tmux.conf.
  if [[ "$DRY" == "false" ]]; then
    clone_if_missing "tmux-yank" \
      "https://github.com/tmux-plugins/tmux-yank.git" \
      "$HOME/.tmux/plugins/tmux-yank"
    clone_if_missing "catppuccin for tmux" \
      "https://github.com/catppuccin/tmux.git" \
      "$HOME/.tmux/plugins/catppuccin/tmux" \
      -b v2.1.2
  fi
  success "Finished installing tmux plugins"
}

function install_codex_plugins {
  info "Installing codex plugins..."
  # Codex keeps its marketplace/plugin state and plugin cache in the
  # machine-local ~/.codex/config.toml (never tracked). dotfiles.config.toml
  # declares the plugins for `codex -p dotfiles`, but the plugin CACHE must be
  # populated locally or runtime activation silently no-ops. These commands do
  # that and are idempotent. `codex plugin*` rejects -p, but the
  # `codex -p dotfiles` alias isn't active in this non-interactive shell, so
  # plain `codex` resolves to the real binary.
  #
  # ponytail needs its marketplace added first. Superpowers ships in the
  # built-in `openai-curated` marketplace, which codex only populates after
  # `codex login` *and* an interactive `/plugins` picker session — `codex
  # login status` alone isn't sufficient. If the install fails, we print the
  # recovery steps instead of dying.
  if [[ "$DRY" == "false" ]] && command -v codex >/dev/null 2>&1; then
    codex plugin marketplace add DietrichGebert/ponytail \
      || fail "Failed to add ponytail marketplace for codex"
    codex plugin add ponytail@ponytail \
      || fail "Failed to install ponytail plugin for codex"
    if codex login status >/dev/null 2>&1 \
       && codex plugin add superpowers@openai-curated >/dev/null 2>&1; then
      info "Installed superpowers plugin for codex"
    else
      # Use `user` (yellow ?? prefix, ignores QUIET) so this action item is
      # impossible to miss in a long `dotfile` run.
      user "Codex superpowers plugin skipped (openai-curated marketplace not ready)."
      user "  To finish installation:"
      user "    1) codex login    # if not already logged in"
      user "    2) codex          # open the TUI once, /plugins, then quit"
      user "    3) dotfile extras"
    fi
  fi
  success "Finished installing codex plugins"
}

function install_opencode_plugins {
  info "Installing opencode plugins..."
  # Claude and Codex install ponytail via their own plugin marketplaces, but
  # OpenCode has no marketplace for it. Its plugin loads sibling hooks/ and
  # skills/ relative to its own file, so it needs a full checkout. We own a
  # stable clone here (the tool caches are version-pinned) and point
  # opencode.json at ~/.local/share/ponytail/.opencode/plugins/ponytail.mjs.
  # Hardcode ~/.local/share (not $XDG_DATA_HOME) so this path matches the
  # ~-relative one in opencode.json, which can't expand an env var.
  if [[ "$DRY" == "false" ]]; then
    local ponytail_dir="$HOME/.local/share/ponytail"
    clone_if_missing "ponytail (opencode)" \
      "https://github.com/DietrichGebert/ponytail.git" \
      "$ponytail_dir"
    # The /ponytail commands are plain markdown OpenCode only discovers from a
    # command dir; link them into the global one so they work outside a checkout.
    local cmd_dst="$HOME/.config/opencode/command"
    mkdir -p "$cmd_dst" || fail "Failed to create $cmd_dst"
    local cmd
    for cmd in "$ponytail_dir"/.opencode/command/*.md; do
      [[ -e "$cmd" ]] || continue
      ln -sf "$cmd" "$cmd_dst/$(basename "$cmd")"
    done
  fi
  success "Finished installing opencode plugins"
}

function install_extras {
  info "Installing extras"
  install_zsh_plugins
  install_tmux_plugins
  install_codex_plugins
  install_opencode_plugins
  success "Finished installing extras"
}
