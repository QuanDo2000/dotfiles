#!/usr/bin/env bash
# Language toolchains are managed by Nix/Home Manager on Unix.
set -eo pipefail

_language_label() {
  case "${1:-all}" in
    zig) echo "Zig" ;;
    odin) echo "Odin" ;;
    gleam) echo "Gleam" ;;
    jank) echo "Jank" ;;
    *) fail "Unknown language: $1" ;;
  esac
}

_language_platform() {
  local platform
  platform="$(detect_platform)"
  [[ "$platform" == "unknown" ]] && platform="Unix"
  echo "$platform"
}

_skip_language() {
  local label="$1"
  info "$label is managed by Home Manager on $(_language_platform); skipping"
}

install_languages() {
  case "${1:-all}" in
    all|"")
      _skip_language Zig
      _skip_language Odin
      _skip_language Gleam
      _skip_language Jank
      ;;
    zig|odin|gleam|jank)
      _skip_language "$(_language_label "$1")"
      ;;
    *)
      fail "Unknown language: $1"
      ;;
  esac
}

update_languages() {
  install_languages all
}
