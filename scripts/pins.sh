#!/usr/bin/env bash
set -eo pipefail

function _run_pin_updater {
  local target="$1" label="$2"
  if [[ "$DRY" == "true" ]]; then
    info "Would update $label"
    return
  fi
  info "Updating $label..."
  nix develop "path:$DOTFILES_DIR" -c \
    python3 "$DOTFILES_DIR/scripts/update_pins.py" "$target" "$DOTFILES_DIR" \
    || fail "Failed to update $label"
}

function _update_codebase_memory_release { _run_pin_updater codebase-memory "codebase-memory release"; }
function _update_fff_release { _run_pin_updater fff "FFF release"; }
function _update_pi_extensions_release { _run_pin_updater pi-extensions "Pi extension closure"; }
function _update_webcord_release { _run_pin_updater webcord "WebCord release"; }
function _update_anki_zoom { _run_pin_updater anki-zoom "Anki Zoom add-on"; }
function _update_firacode_pin { _run_pin_updater firacode "FiraCode Nerd Font"; }
function _update_vendored_skills { _run_pin_updater skills "vendored agent skills"; }
function _update_neovim_plugins { _run_pin_updater neovim "Neovim plugins"; }
