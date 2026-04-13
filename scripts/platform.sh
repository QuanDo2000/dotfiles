#!/bin/bash
# Platform detection helpers. Source after utils.sh.
set -eo pipefail

is_mac() { [[ "$(uname)" == "Darwin" ]]; }
is_linux() { [[ "$(uname)" == "Linux" ]]; }

# Print one of: debian, arch, mac, unknown
detect_platform() {
  if is_mac; then
    echo "mac"
    return
  fi
  if is_linux && [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    local ID="" ID_LIKE=""
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
      echo "debian"
      return
    fi
    if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
      echo "arch"
      return
    fi
  fi
  echo "unknown"
}

# Resolve a symlink target to an absolute path (portable: macOS lacks readlink -f).
# Usage: resolve_symlink <path>
resolve_symlink() {
  local target="$1"
  local link
  link="$(readlink "$target")" || return 1
  if [[ "$link" != /* ]]; then
    link="$(cd -P "$(dirname "$target")" && pwd)/$link"
  fi
  echo "$link"
}
