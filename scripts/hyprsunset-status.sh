#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"
if [[ ! -f "$config" ]]; then
  config="$repo/config/unix/config/hypr/hyprsunset.conf"
fi

times="$(awk '$1 == "time" && $2 == "=" { print $3 }' "$config")"
day="$(awk 'NR == 1 { print; exit }' <<<"$times")"
night="$(awk 'NR == 2 { print; exit }' <<<"$times")"
day="${day:-07:00}"
night="${night:-20:00}"
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
