#!/bin/bash
set -eo pipefail

# Default globals if not set by caller
: "${DRY:=false}"
: "${QUIET:=false}"
: "${FORCE:=false}"

info() {
  [[ "$QUIET" == "true" && "${2:-}" != "--force" ]] && return
  local prefix=""
  [[ "$DRY" == "true" ]] && prefix="[DRY] "
  printf '\r  [ \033[00;34m..\033[0m ] %s%s\n' "$prefix" "$1"
}

user() {
  printf '\r  [ \033[0;33m??\033[0m ] %b\n' "$1"
}

success() {
  [[ "$QUIET" == "true" && "${2:-}" != "--force" ]] && return
  printf '\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n' "$1"
}

fail() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
  echo ''
  exit 1
}

fail_soft() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
}
