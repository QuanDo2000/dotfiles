#!/bin/bash
# Language toolchain installers (Linux + macOS only).
# Sourced by `dotfile`. Requires utils.sh, platform.sh, packages.sh already sourced.
set -eo pipefail

# Zig signing public key. Source: https://ziglang.org/download/  Copied: 2026-04-17
# Re-check periodically; the Zig project rarely rotates this but does occasionally.
ZIG_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

# Portable sha256 of a file. Linux ships sha256sum; macOS ships shasum.
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Portable line shuffle. Reads stdin, prints lines in random order on stdout.
# `shuf` is GNU coreutils — present on Linux but not stock macOS, so we use awk.
_shuffle_lines() {
  awk 'BEGIN { srand() } { lines[NR] = $0 } END {
    for (i = NR; i > 1; i--) {
      j = int(rand() * i) + 1
      t = lines[i]; lines[i] = lines[j]; lines[j] = t
    }
    for (i = 1; i <= NR; i++) print lines[i]
  }'
}

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

# Map (uname -s, uname -m) to Gleam's release-asset triple (Rust-style).
# Linux uses musl for static linking (no glibc version coupling).
gleam_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "x86_64-unknown-linux-musl" ;;
    Linux/aarch64)       echo "aarch64-unknown-linux-musl" ;;
    Linux/arm64)         echo "aarch64-unknown-linux-musl" ;;
    Darwin/x86_64)       echo "x86_64-apple-darwin" ;;
    Darwin/arm64)        echo "aarch64-apple-darwin" ;;
    Darwin/aarch64)      echo "aarch64-apple-darwin" ;;
    *) fail "Unsupported platform for gleam install: $os/$arch" ;;
  esac
}

# Install jq via the platform package manager if missing.
# Called by install_zig before zig_latest_stable runs, so jq is guaranteed
# available at the point where index.json gets parsed.
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
# Only accepts keys matching three-component semver (e.g. 0.14.1); rejects
# "master" and any pre-release keys like "0.15.0-rc1".
#
# If a JSON string is passed as $1, parse that instead of fetching. Lets
# install_zig fetch index.json once and reuse it for both the version pick
# and the shasum cross-check, halving the network round-trips.
zig_latest_stable() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://ziglang.org/download/index.json")" \
      || fail "Failed to fetch Zig index.json"
  fi
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

# Install (or upgrade) Zig from the official community mirrors with full
# minisign signature verification + sha256 cross-check.
#
# Layout: extracts to ~/.local/zig-<version>/ and symlinks ~/.local/bin/zig.
# Skips if the target version is already installed (per zig_current_installed_version).
install_zig() {
  info "Installing Zig..."
  ensure_minisign
  ensure_jq

  local triple
  triple="$(zig_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest stable Zig for $triple"
    success "Finished installing Zig (dry run)"
    return 0
  fi

  # Single index.json fetch reused for both version pick and shasum lookup.
  local index_json
  index_json="$(http_get_retry "https://ziglang.org/download/index.json")" \
    || fail "Failed to fetch Zig index.json"

  local version
  version="$(zig_latest_stable "$index_json")"
  local tarball="zig-${triple}-${version}.tar.xz"

  local current
  current="$(zig_current_installed_version)"
  if [[ "$current" == "$version" ]]; then
    success "Already installed Zig $version"
    return 0
  fi

  local shasum
  shasum="$(echo "$index_json" | jq -r --arg v "$version" --arg t "$triple" \
    '.[$v][$t].shasum // empty')"
  if [[ -z "$shasum" ]]; then
    fail "Could not find shasum for $version/$triple in index.json"
  fi

  local mirrors_text mirror tmpdir
  mirrors_text="$(http_get_retry "https://ziglang.org/download/community-mirrors.txt")" \
    || fail "Failed to fetch community-mirrors.txt"
  if [[ -z "${mirrors_text//[[:space:]]/}" ]]; then
    fail "community-mirrors.txt was empty — Zig has no published mirrors right now"
  fi
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tar_path="$tmpdir/$tarball"
  local sig_path="$tar_path.minisig"
  local got_it=false actual got_sha tried=0
  while IFS= read -r mirror; do
    [[ -z "$mirror" ]] && continue
    tried=$((tried + 1))
    info "Trying mirror: $mirror"
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
    actual="$(grep -m1 '^trusted comment:' "$sig_path" \
      | sed -n 's/.*file:\([^[:space:]]*\).*/\1/p')"
    if [[ "$actual" != "$tarball" ]]; then
      info "Signed filename mismatch (got '$actual'); trying next mirror"
      continue
    fi
    # Defense-in-depth sha256 check
    got_sha="$(_sha256 "$tar_path")"
    if [[ "$got_sha" != "$shasum" ]]; then
      info "sha256 mismatch; trying next mirror"
      continue
    fi
    got_it=true
    break
  done < <(echo "$mirrors_text" | _shuffle_lines)

  if [[ "$got_it" != "true" ]]; then
    fail "Could not fetch a verified Zig tarball after trying $tried mirror(s). Re-run, check your network, or download manually from https://ziglang.org/download/"
  fi

  # Extract to a temp subdir, then move to ~/.local/zig-<version>/.
  # The upstream tarball top-level is zig-<arch>-<os>-<version>/; we strip
  # the arch portion when moving so zig_current_installed_version's parsing
  # rule stays simple.
  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tar_path" -C "$extract_dir" \
    || fail "Failed to extract Zig tarball"
  # Portable single-dir check (avoid mapfile/-readarray for bash 3.2 on macOS).
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "Tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi

  local target_dir="$HOME/.local/zig-$version"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Zig into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/zig" "$HOME/.local/bin/zig" \
    || fail "Failed to create ~/.local/bin/zig symlink"

  # Clean up old versions (any ~/.local/zig-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/zig-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Zig $version"
}

# Update Zig — but only if it was installed by this script. Foreign installs
# (system, brew, scoop) are left alone.
update_zig() {
  local current
  current="$(zig_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_zig
}

# Umbrella: install all languages, or just one if specified.
# Usage: install_languages [LANG]
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig; install_odin ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    *)      fail "Unknown language: $target" ;;
  esac
}

# Print the currently-installed Odin tag IF it was installed by this script.
# Returns empty string for: no install, foreign install (e.g., system odin).
# Detection rule: ~/.local/bin/odin must be a symlink whose target is
# ~/.local/odin-<tag>/odin.
odin_current_installed_version() {
  local link="$HOME/.local/bin/odin"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  local prefix="$HOME/.local/odin-"
  local suffix="/odin"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#$prefix}"
      middle="${middle%$suffix}"
      case "$middle" in
        */*) return 0 ;;
      esac
      echo "$middle"
      ;;
  esac
}

# Map (uname -s, uname -m) to Odin's release-asset slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
odin_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "linux-amd64" ;;
    Linux/aarch64)       echo "linux-arm64" ;;
    Linux/arm64)         echo "linux-arm64" ;;
    Darwin/x86_64)       echo "macos-amd64" ;;
    Darwin/arm64)        echo "macos-arm64" ;;
    Darwin/aarch64)      echo "macos-arm64" ;;
    *) fail "Unsupported platform for odin install: $os/$arch" ;;
  esac
}

# Print the JSON body of the latest Odin release from the GitHub API.
# Optionally accepts a JSON string as $1 to skip the network fetch — lets
# install_odin fetch once and reuse the body for tag/digest/url lookups.
odin_latest_release() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://api.github.com/repos/odin-lang/Odin/releases/latest")" \
      || fail "Failed to fetch Odin releases/latest"
  fi
  echo "$json"
}

# Install (or upgrade) Odin from the official GitHub releases.
#
# Layout: extracts to ~/.local/odin-<tag>/ and symlinks ~/.local/bin/odin.
# Skips if the target tag is already installed.
install_odin() {
  info "Installing Odin..."
  ensure_jq

  local triple
  triple="$(odin_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Odin for $triple"
    success "Finished installing Odin (dry run)"
    return 0
  fi

  local release_json
  release_json="$(odin_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Odin releases/latest"
  fi
  local asset="odin-${triple}-${tag}.tar.gz"

  local current
  current="$(odin_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Odin $tag"
    return 0
  fi

  local digest
  digest="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // empty')"
  if [[ -z "$digest" ]]; then
    fail "Could not find digest for $asset in Odin releases/latest"
  fi
  # GitHub formats digests as "sha256:<hex>"; strip the prefix.
  # If the prefix is absent (e.g. "sha512:" or bare hex), the expansion is a
  # no-op, so expected_sha == digest — fail loudly rather than compare against
  # a value of unknown algorithm.
  local expected_sha="${digest#sha256:}"
  if [[ "$expected_sha" == "$digest" ]]; then
    fail "Unexpected digest format for $asset: $digest"
  fi

  local asset_url
  asset_url="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .browser_download_url // empty')"
  if [[ -z "$asset_url" ]]; then
    fail "Could not find download URL for $asset in Odin releases/latest"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tar_path="$tmpdir/$asset"
  info "Downloading $asset_url"
  curl -sfL "$asset_url" -o "$tar_path" \
    || fail "Failed to download $asset_url"

  local got_sha
  got_sha="$(_sha256 "$tar_path")"
  if [[ "$got_sha" != "$expected_sha" ]]; then
    fail "sha256 mismatch for $asset (expected $expected_sha, got $got_sha)"
  fi

  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tar_path" -C "$extract_dir" \
    || fail "Failed to extract Odin tarball"
  # Portable single-dir check (avoid mapfile/-readarray for bash 3.2 on macOS).
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "Odin tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi

  local target_dir="$HOME/.local/odin-$tag"
  rm -rf "$target_dir"
  mv "$extracted" "$target_dir" || fail "Failed to move Odin into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/odin" "$HOME/.local/bin/odin" \
    || fail "Failed to create ~/.local/bin/odin symlink"

  # Clean up old versions (any ~/.local/odin-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/odin-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Odin $tag"
}

# Update Odin — but only if it was installed by this script. Foreign installs
# (system, brew) are left alone.
update_odin() {
  local current
  current="$(odin_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_odin
}

# Print the JSON body of the latest Gleam release from the GitHub API.
# Optionally accepts a JSON string as $1 to skip the network fetch — lets
# install_gleam fetch once and reuse the body for tag/digest/url lookups.
gleam_latest_release() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://api.github.com/repos/gleam-lang/gleam/releases/latest")" \
      || fail "Failed to fetch Gleam releases/latest"
  fi
  echo "$json"
}

# Update every language that this script previously installed.
update_languages() {
  update_zig
  update_odin
}
