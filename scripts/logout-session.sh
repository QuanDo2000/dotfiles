#!/usr/bin/env bash
set -euo pipefail

chrome_addresses() {
  hyprctl -j clients 2>/dev/null \
    | jq -r '.[] | select(.class == "google-chrome") | .address' 2>/dev/null \
    || true
}

for address in $(chrome_addresses); do
  hyprctl dispatch closewindow "address:$address" >/dev/null 2>&1 || true
done

# Give Chrome time to save its profile after its last window closes.
for _ in {1..100}; do
  pgrep -x chrome >/dev/null || break
  sleep 0.1
done

if pgrep -x chrome >/dev/null; then
  command -v notify-send >/dev/null && notify-send "Log out cancelled" "Chrome is still closing"
  exit 1
fi

exec uwsm stop
