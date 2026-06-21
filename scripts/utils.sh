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

fail_soft() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
}

fail() {
  fail_soft "$1"
  echo ''
  exit 1
}

# Fetch a URL with retry + exponential backoff. Useful for GitHub API calls
# which are rate-limited to 60 req/hr unauthenticated.
# Usage: http_get_retry <url> [output-file]
function http_get_retry {
  local url="$1" out="${2:-}"
  local attempt=1 max=4 delay=2
  while (( attempt <= max )); do
    if [[ -n "$out" ]]; then
      if curl -sfL --retry 2 -o "$out" "$url"; then return 0; fi
    else
      if curl -sfL --retry 2 "$url"; then return 0; fi
    fi
    if (( attempt < max )); then
      info "curl $url failed (attempt $attempt/$max); retrying in ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  return 1
}
