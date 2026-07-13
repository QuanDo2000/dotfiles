#!/usr/bin/env bash
set -euo pipefail

bindings() {
  hyprctl binds -j | jq -r '
    def has($bit): ((.modmask / $bit | floor) % 2) == 1;
    def mods: [
      if has(64) then "SUPER" else empty end,
      if has(4) then "CTRL" else empty end,
      if has(8) then "ALT" else empty end,
      if has(1) then "SHIFT" else empty end
    ];
    .[]
    | select(.description != "")
    | [((if (.submap // "") != "" then "[" + .submap + "] " else "" end) + ((mods + [.key]) | join("+"))), .description]
    | @tsv
  ' | sort -u
}

if [[ "${1:-}" == "--print" ]]; then
  bindings
else
  bindings | fuzzel --dmenu --prompt "Keybinds: " --width 70 --lines 20 >/dev/null
fi
