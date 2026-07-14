#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--next" ]]; then
  case "$(fcitx5-remote -n 2>/dev/null || true)" in
    keyboard-us) next=unikey ;;
    unikey) next=pinyin ;;
    *) next=keyboard-us ;;
  esac
  exec fcitx5-remote -s "$next"
fi

input_method="${1:-$(fcitx5-remote -n 2>/dev/null || true)}"
case "$input_method" in
  keyboard-us) text="󰌌 EN"; tooltip="Keyboard: English" ;;
  unikey) text="󰌌 VI"; tooltip="Keyboard: Vietnamese (Unikey)" ;;
  pinyin) text="󰌌 中"; tooltip="Keyboard: Chinese (Pinyin)" ;;
  *) text="󰌌 ?"; tooltip="Keyboard input unavailable" ;;
esac

jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text: $text, tooltip: $tooltip}'
