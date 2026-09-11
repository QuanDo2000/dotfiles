#!/usr/bin/env bash
set -euo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprsunset.conf"
day=07:00
night=20:00
temperature=4500
if [[ -f "$config" ]]; then
  read -r day night temperature < <(awk '
    $1 == "time" && $2 == "=" { if (!day) day=$3; else if (!night) night=$3 }
    $1 == "temperature" && $2 == "=" { temperature=$3 }
    END { print day, night, temperature }
  ' "$config")
  day="${day:-07:00}"
  night="${night:-20:00}"
  temperature="${temperature:-4500}"
fi
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
