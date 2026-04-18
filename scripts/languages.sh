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

# Install (or upgrade) Zig from the official community mirrors with full
# minisign signature verification + sha256 cross-check.
#
# Layout: extracts to ~/.local/zig-<version>/ and symlinks ~/.local/bin/zig.
# Skips if the target version is already installed (per zig_current_installed_version).
install_zig() {
  info "Installing Zig..."
  ensure_minisign
  ensure_jq

  local triple version
  triple="$(zig_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest stable Zig for $triple"
    success "Finished installing Zig (dry run)"
    return 0
  fi

  version="$(zig_latest_stable)"
  local tarball="zig-${triple}-${version}.tar.xz"

  local current
  current="$(zig_current_installed_version)"
  if [[ "$current" == "$version" ]]; then
    success "Already installed Zig $version"
    return 0
  fi

  # Cross-check: pull the expected sha256 from index.json for this triple.
  local index_json shasum
  index_json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"
  shasum="$(echo "$index_json" | jq -r --arg v "$version" --arg t "$triple" \
    '.[$v][$t].shasum // empty')"
  if [[ -z "$shasum" ]]; then
    fail "Could not find shasum for $version/$triple in index.json"
  fi

  # Mirror loop with verification
  local mirrors_text mirror tmpdir
  mirrors_text="$(http_get_retry "https://ziglang.org/download/community-mirrors.txt")" \
    || fail "Failed to fetch community-mirrors.txt"
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local got_it=false
  while IFS= read -r mirror; do
    [[ -z "$mirror" ]] && continue
    info "Trying mirror: $mirror"
    local tar_path="$tmpdir/$tarball"
    local sig_path="$tar_path.minisig"
    rm -f "$tar_path" "$sig_path"

    if ! curl -sfL "$mirror/$tarball?source=quando-dotfiles" -o "$tar_path"; then
      continue
    fi
    if ! curl -sfL "$mirror/$tarball.minisig?source=quando-dotfiles" -o "$sig_path"; then
      continue
    fi
    if ! minisign -V -P "$ZIG_PUBKEY" -m "$tar_path" -x "$sig_path" >/dev/null 2>&1; then
      info "Signature verification failed; trying next mirror"
      continue
    fi
    # Downgrade-attack guard: parse trusted comment for `file:` field
    local actual
    actual="$(grep -m1 '^trusted comment:' "$sig_path" \
      | sed -n 's/.*file:\([^[:space:]]*\).*/\1/p')"
    if [[ "$actual" != "$tarball" ]]; then
      info "Signed filename mismatch (got '$actual'); trying next mirror"
      continue
    fi
    # Defense-in-depth sha256 check
    local got_sha
    got_sha="$(sha256sum "$tar_path" | awk '{print $1}')"
    if [[ "$got_sha" != "$shasum" ]]; then
      info "sha256 mismatch; trying next mirror"
      continue
    fi
    got_it=true
    break
  done < <(echo "$mirrors_text" | shuf)

  if [[ "$got_it" != "true" ]]; then
    fail "Could not fetch a verified Zig tarball from any mirror"
  fi

  # Extract to a temp subdir, then move to ~/.local/zig-<version>/
  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tmpdir/$tarball" -C "$extract_dir" \
    || fail "Failed to extract Zig tarball"
  local extracted
  extracted="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$extracted" ]] || fail "Tarball extracted to an unexpected layout"

  local target_dir="$HOME/.local/zig-$version"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Zig into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/zig" "$HOME/.local/bin/zig" \
    || fail "Failed to create ~/.local/bin/zig symlink"

  # Clean up old versions (any ~/.local/zig-*/ that isn't the current one)
  local old
  for old in "$HOME"/.local/zig-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Zig $version"
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
