#!/bin/bash
# Language toolchain installers (Linux + macOS only).
# Sourced by `dotfile`. Requires utils.sh, platform.sh, packages.sh already sourced.
set -eo pipefail

# Zig signing public key. Source: https://ziglang.org/download/  Copied: 2026-04-17
# Re-check periodically; the Zig project rarely rotates this but does occasionally.
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

# Map (uname -s, uname -m) to Zig's tarball arch slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
zig_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "x86_64-linux" ;;
    Linux/aarch64)       echo "aarch64-linux" ;;
    Linux/arm64)         echo "aarch64-linux" ;;
    Darwin/x86_64)       echo "x86_64-macos" ;;
    Darwin/arm64)        echo "aarch64-macos" ;;
    Darwin/aarch64)      echo "aarch64-macos" ;;
    *) fail "Unsupported platform for zig install: $os/$arch" ;;
  esac
}

# Install jq via the platform package manager if missing. Used by zig_latest_stable.
ensure_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  info "jq not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y jq || fail "Failed to install jq" ;;
    arch)   sudo pacman -S --needed --noconfirm jq || fail "Failed to install jq" ;;
    mac)    brew install jq || fail "Failed to install jq" ;;
    *)      fail "Cannot install jq on this platform" ;;
  esac
  success "Installed jq"
}

# Print the highest stable Zig version from the official index.json.
# Skips the "master" key (development build).
zig_latest_stable() {
  local json
  json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"
  local version
  version="$(echo "$json" | jq -r '
    keys_unsorted
    | map(select(. != "master"))
    | sort_by(split(".") | map(tonumber? // 0))
    | last // empty
  ')" || fail "Failed to parse Zig index.json"
  if [[ -z "$version" ]]; then
    fail "No stable Zig version found in index.json"
  fi
  echo "$version"
}
