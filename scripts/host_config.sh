#!/usr/bin/env bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

host_config_value_from_file() {
  local key="$1"
  local host_config="$DOTFILES_DIR/config/host.nix"
  local pattern="(^|[[:space:]{;])${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;"
  local line

  [[ -f "$host_config" ]] || return 1
  while IFS= read -r line; do
    if [[ "$line" =~ $pattern ]]; then
      printf '%s\n' "${BASH_REMATCH[2]}"
      return 0
    fi
  done < "$host_config"
  return 1
}

host_config_value() {
  local output status=0
  output="$(nix eval --raw --file "$DOTFILES_DIR/config/host.nix" "$1" 2>/dev/null)" || status=$?
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "$output"
    return 0
  fi

  if [[ "$status" -eq 127 ]]; then
    host_config_value_from_file "$1"
    return
  fi
  return "$status"
}
