#!/usr/bin/env bash
set -eo pipefail

# Release pin discovery, hashing, and tracked package updates.

function _latest_codex_release_tag {
  local release_url tag
  release_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/openai/codex/releases/latest)" \
    || fail "Failed to check latest Codex release"
  tag="${release_url##*/}"
  [[ "$tag" == rust-v* ]] || fail "Unexpected Codex release tag: $tag"
  printf '%s\n' "$tag"
}

function _codex_release_archive_url {
  local tag platform version
  tag="$1"
  platform="${2:-linux}"
  version="${tag#rust-v}"

  case "$platform" in
    linux)  printf 'https://github.com/openai/codex/releases/download/%s/codex-package-x86_64-unknown-linux-musl.tar.gz\n' "$tag" ;;
    darwin) printf 'https://github.com/openai/codex/releases/download/%s/openai_codex_cli_bin-%s-py3-none-macosx_11_0_arm64.whl\n' "$tag" "$version" ;;
    *)      fail "Unsupported Codex release platform: $platform" ;;
  esac
}

function _prefetch_codex_release_hash {
  local tag platform url output hash
  tag="$1"
  platform="${2:-linux}"
  url="$(_codex_release_archive_url "$tag" "$platform")"
  output="$(nix store prefetch-file --json --hash-type sha256 "$url")" \
    || fail "Failed to prefetch Codex release archive"
  hash="$(jq -r '.hash // empty' <<< "$output")"
  [[ -n "$hash" ]] || fail "Failed to parse Codex release archive hash"
  printf '%s\n' "$hash"
}

function _write_codex_release_package {
  local tag linux_hash darwin_hash version package_file tmp
  tag="$1"
  linux_hash="$2"
  darwin_hash="$3"
  version="${tag#rust-v}"
  package_file="$DOTFILES_DIR/packages/codex-release.nix"
  [[ -f "$package_file" ]] || fail "Missing Codex package file: $package_file"

  tmp="$(mktemp)" || fail "Failed to create temp file"
  sed -E \
    -e 's#version = "[^"]+";#version = "'"$version"'";#' \
    -e 's#linuxHash = "[^"]+";#linuxHash = "'"$linux_hash"'";#' \
    -e 's#darwinHash = "[^"]+";#darwinHash = "'"$darwin_hash"'";#' \
    "$package_file" > "$tmp" \
    && mv "$tmp" "$package_file" \
    || fail "Failed to update Codex package file"
}

function _update_codex_release_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Codex package from the latest GitHub release"
    return
  fi

  local tag linux_hash darwin_hash version package_file current_version
  package_file="$DOTFILES_DIR/packages/codex-release.nix"
  [[ -f "$package_file" ]] || fail "Missing Codex package file: $package_file"
  tag="$(_latest_codex_release_tag)"
  version="${tag#rust-v}"
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Codex package already at $tag"
    return
  fi

  info "Updating Codex package to $tag..."
  _ensure_nix
  linux_hash="$(_prefetch_codex_release_hash "$tag" linux)"
  darwin_hash="$(_prefetch_codex_release_hash "$tag" darwin)"
  _write_codex_release_package "$tag" "$linux_hash" "$darwin_hash"
}

function _latest_npm_package_version {
  local package metadata version
  package="$1"
  metadata="$(curl -fsSL "https://registry.npmjs.org/$package/latest")" \
    || fail "Failed to check latest $package release"
  version="$(printf '%s\n' "$metadata" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [[ -n "$version" ]] || fail "Failed to parse latest $package version"
  printf '%s\n' "$version"
}

function _obsidian_headless_archive_url {
  printf 'https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-%s.tgz\n' "$1"
}

function _prefetch_obsidian_headless_src_hash {
  local version url output hash
  version="$1"
  url="$(_obsidian_headless_archive_url "$version")"
  output="$(nix store prefetch-file --json --hash-type sha256 "$url")" \
    || fail "Failed to prefetch Obsidian Headless archive"
  hash="$(jq -r '.hash // empty' <<< "$output")"
  [[ -n "$hash" ]] || fail "Failed to parse Obsidian Headless archive hash"
  printf '%s\n' "$hash"
}

function _download_obsidian_headless_package_lock {
  local version url lock_file tmp_dir tarball
  version="$1"
  lock_file="${2:-$DOTFILES_DIR/packages/obsidian-headless-package-lock.json}"
  url="$(_obsidian_headless_archive_url "$version")"
  tmp_dir="$(mktemp -d)" || fail "Failed to create temp dir"
  tarball="$tmp_dir/obsidian-headless.tgz"
  curl -fsSL "$url" -o "$tarball" \
    || { rm -rf "$tmp_dir"; fail "Failed to download Obsidian Headless archive"; }
  tar -xOzf "$tarball" package/package-lock.json > "$lock_file" \
    || { rm -rf "$tmp_dir"; fail "Failed to extract Obsidian Headless package lock"; }
  rm -rf "$tmp_dir"
}

function _prefetch_obsidian_headless_npm_deps_hash {
  local lock_file
  lock_file="${1:-$DOTFILES_DIR/packages/obsidian-headless-package-lock.json}"
  nix run nixpkgs#prefetch-npm-deps -- "$lock_file" \
    || fail "Failed to prefetch Obsidian Headless npm deps"
}

function _write_obsidian_headless_package {
  local version src_hash deps_hash package_file output_file tmp
  version="$1"
  src_hash="$2"
  deps_hash="$3"
  package_file="$DOTFILES_DIR/packages/obsidian-headless.nix"
  output_file="${4:-$package_file}"
  [[ -f "$package_file" ]] || fail "Missing Obsidian Headless package file: $package_file"

  tmp="$output_file"
  if [[ "$output_file" == "$package_file" ]]; then
    tmp="$(mktemp)" || fail "Failed to create temp file"
  fi

  sed -E \
    -e 's#version = "[^"]+";#version = "'"$version"'";#' \
    -e 's#^([[:space:]]*hash = ")[^"]+(";)$#\1'"$src_hash"'\2#' \
    -e 's#npmDepsHash = "[^"]+";#npmDepsHash = "'"$deps_hash"'";#' \
    "$package_file" > "$tmp" \
    || fail "Failed to update Obsidian Headless package file"
  [[ "$tmp" == "$output_file" ]] \
    || mv "$tmp" "$package_file" \
    || fail "Failed to update Obsidian Headless package file"
}

function _update_obsidian_headless_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Obsidian Headless package from the latest npm release"
    return
  fi

  local version current_version package_file lock_file src_hash deps_hash tmp_package tmp_lock
  package_file="$DOTFILES_DIR/packages/obsidian-headless.nix"
  lock_file="$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"
  [[ -f "$package_file" ]] || fail "Missing Obsidian Headless package file: $package_file"
  version="$(_latest_npm_package_version obsidian-headless)"
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Obsidian Headless package already at $version"
    return
  fi

  info "Updating Obsidian Headless package to $version..."
  _ensure_nix
  tmp_package="$(mktemp)" || fail "Failed to create temp file"
  tmp_lock="$(mktemp)" || fail "Failed to create temp file"

  if ! src_hash="$(_prefetch_obsidian_headless_src_hash "$version")"; then
    printf '%s\n' "$src_hash"
    rm -f "$tmp_package" "$tmp_lock"
    return 1
  fi
  _download_obsidian_headless_package_lock "$version" "$tmp_lock"
  if ! deps_hash="$(_prefetch_obsidian_headless_npm_deps_hash "$tmp_lock")"; then
    printf '%s\n' "$deps_hash"
    rm -f "$tmp_package" "$tmp_lock"
    return 1
  fi

  _write_obsidian_headless_package "$version" "$src_hash" "$deps_hash" "$tmp_package"
  mv "$tmp_package" "$package_file" \
    && mv "$tmp_lock" "$lock_file" \
    || fail "Failed to install updated Obsidian Headless package files"
}

function update_codex_release {
  info "Updating pinned Codex release package..."
  _update_codex_release_package
  success "Finished updating pinned Codex release package"
}

function update_obsidian_headless_release {
  info "Updating pinned Obsidian Headless package..."
  _update_obsidian_headless_package
  success "Finished updating pinned Obsidian Headless package"
}
