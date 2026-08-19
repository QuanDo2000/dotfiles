#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

host_config_value_from_file() {
  local key="$1"
  local host_config="$DOTFILES_DIR/config/host.nix"
  local content canonical_pattern pattern

  [[ "$key" =~ ^[[:alpha:]_][[:alnum:]_-]*$ ]] || return 1
  [[ -f "$host_config" ]] || return 1
  content="$(<"$host_config")"
  [[ "$content" != *\\* ]] || return 1
  canonical_pattern='^[[:space:]]*\{([[:space:]]*[[:alpha:]_][[:alnum:]_-]*[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*;)*[[:space:]]*\}[[:space:]]*$'
  [[ "$content" =~ $canonical_pattern ]] || return 1

  pattern="(^|[[:space:]{;])${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;"
  [[ "$content" =~ $pattern ]] || return 1
  printf '%s\n' "${BASH_REMATCH[2]}"
}

host_config_value() {
  local output status=0
  if output="$(host_config_value_from_file "$1")"; then
    printf '%s\n' "$output"
    return 0
  fi

  output="$(nix eval --raw --file "$DOTFILES_DIR/config/host.nix" "$1" 2>/dev/null)" || status=$?
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "$output"
    return 0
  fi
  return "$status"
}
