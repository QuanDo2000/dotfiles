#!/usr/bin/env bash
set -eo pipefail

# Default globals if not set by caller
: "${DRY:=false}"
: "${QUIET:=false}"
: "${FORCE:=false}"

# Human-readable output only; callers returning data keep their own stdout.
_log() {
  local label="$1" message="$2" color="$3" line first=true
  while IFS= read -r line; do
    if [[ "$first" == true ]]; then
      # Logged updates retain the original stdout on FD 6 before piping it.
      if { [[ -t 1 ]] || [[ -n "${DOTFILE_UPDATE_LOG:-}" && -t 6 ]]; } \
        && [[ "${TERM:-}" != dumb && -z "${NO_COLOR:-}" ]]; then
        printf '  [\033[%sm%s\033[0m] %s\n' "$color" "$label" "$line"
      else
        printf '  [%s] %s\n' "$label" "$line"
      fi
      first=false
    else
      printf '         %s\n' "$line"
    fi
  done <<< "$message"
}

info() {
  [[ "$QUIET" == true && "${2:-}" != --force ]] && return 0
  local label=INFO
  [[ "$DRY" == true ]] && label='DRY '
  _log "$label" "$1" 34
}

user() { _log 'ASK ' "$1" 33; }

warn() { _log WARN "$1" 33; }

success() {
  # Operations may be skipped in dry runs; never claim they completed.
  [[ "$DRY" == true ]] && return 0
  [[ "$QUIET" == true && "${2:-}" != --force ]] && return 0
  _log ' OK ' "$1" 32
}

fail_soft() { _log FAIL "$1" 31; }

fail() {
  fail_soft "$1"
  exit 1
}
