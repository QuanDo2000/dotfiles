#!/usr/bin/env bash
set -eo pipefail

function _run_python_pin_batch {
  local args=() target label
  while [[ $# -gt 0 ]]; do
    target="$1"; label="$2"; shift 2
    args+=("$target")
    if [[ "$DRY" == "true" ]]; then
      info "Would update $label"
    else
      info "Updating $label..."
    fi
  done
  [[ "$DRY" == "true" ]] && return
  nix develop "path:$DOTFILES_DIR" -c \
    python3 "$DOTFILES_DIR/scripts/update_pins.py" "${args[@]}" "$DOTFILES_DIR" \
    || fail "Failed to update Python dependency pins"
}
