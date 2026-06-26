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

function install_opencode_plugins {
  info "Installing opencode plugins..."
  # Claude installs ponytail via its own plugin marketplace, but
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
  install_opencode_plugins
  success "Finished installing extras"
}
