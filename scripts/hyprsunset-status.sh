#!/usr/bin/env bash
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"
if [[ ! -f "$config" ]]; then
  config="${DOTFILES_DIR:-$HOME/dotfiles}/config/unix/config/hypr/hyprsunset.conf"
fi

mapfile -t times < <(awk '$1 == "time" && $2 == "=" { print $3 }' "$config")
day="${times[0]:-07:00}"
night="${times[1]:-20:00}"
temperature="$(awk '$1 == "temperature" && $2 == "=" { print $3; exit }' "$config")"
temperature="${temperature:-4500}"
now="${1:-$(date +%H:%M)}"
running="${HYPRSUNSET_RUNNING:-}"
if [[ -z "$running" ]]; then
  systemctl --user is-active --quiet hyprsunset.service && running=true || running=false
fi

if [[ "$running" != true ]]; then
  text="󰅙"
  tooltip="Night light service is inactive"
  class="disabled"
elif [[ "$now" < "$day" || "$now" > "$night" || "$now" == "$night" ]]; then
  text="󰖔"
  tooltip="$(printf 'Night light: %sK\nNormal colors at %s' "$temperature" "$day")"
  class="active"
else
  text="󰖙"
  tooltip="$(printf 'Night light: inactive\nWarm colors at %s' "$night")"
  class="inactive"
fi

jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
  '{text: $text, tooltip: $tooltip, class: $class}'
