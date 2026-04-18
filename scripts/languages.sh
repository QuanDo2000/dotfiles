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

# Install jq via the platform package manager if missing.
# Called by install_zig (Task 6) before zig_latest_stable runs, so jq is
# guaranteed available at the point where index.json gets parsed.
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
# Only accepts clean three-component semver keys (e.g. 0.14.1) — skips
# "master" and any pre-release keys like "0.15.0-rc1" if Zig ever lists them
# at the top level of the index.
zig_latest_stable() {
  local json
  json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"
  local version
  version="$(echo "$json" | jq -r '
    keys_unsorted
    | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
    | sort_by(split(".") | map(tonumber))
    | last // empty
  ')" || fail "Failed to parse Zig index.json"
  if [[ -z "$version" ]]; then
    fail "No stable Zig version found in index.json"
  fi
  echo "$version"
}

# Install minisign via the platform package manager if missing. Required for
# tarball signature verification.
ensure_minisign() {
  if command -v minisign >/dev/null 2>&1; then
    return 0
  fi
  info "minisign not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y minisign || fail "Failed to install minisign" ;;
    arch)   sudo pacman -S --needed --noconfirm minisign || fail "Failed to install minisign" ;;
    mac)    brew install minisign || fail "Failed to install minisign" ;;
    *)      fail "Cannot install minisign on this platform" ;;
  esac
  success "Installed minisign"
}

# Print the currently-installed Zig version IF it was installed by this script.
# Returns empty string for: no install, foreign install (e.g., system zig).
# Detection rule: ~/.local/bin/zig must be a symlink whose target is
# ~/.local/zig-<version>/zig.
zig_current_installed_version() {
  local link="$HOME/.local/bin/zig"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  # Match $HOME/.local/zig-<version>/zig (use a parameter expansion check
  # rather than regex to stay portable across bash versions).
  local prefix="$HOME/.local/zig-"
  local suffix="/zig"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#$prefix}"
      middle="${middle%$suffix}"
      # Reject if middle still contains a slash (would mean nested dir)
      case "$middle" in
        */*) return 0 ;;
      esac
      echo "$middle"
      ;;
  esac
}
