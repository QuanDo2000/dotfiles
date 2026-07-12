#!/usr/bin/env bash

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pkill waybar || true
exec waybar -c "$repo/config/unix/config/waybar/config.jsonc" -s "$repo/config/unix/config/waybar/style.css"
