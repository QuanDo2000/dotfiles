#!/usr/bin/env bash
set -eo pipefail

# Release pin discovery, hashing, and tracked package updates.

function _write_lix_installer_pins {
  local linux_hash="$1" darwin_hash="$2"
  local packages_file="${3:-$DOTFILES_DIR/scripts/packages.sh}" tmp
  [[ -f "$packages_file" ]] || return 1
  tmp="$(mktemp "${packages_file}.tmp.XXXXXX")" || return 1
  cp -p "$packages_file" "$tmp" || { rm -f "$tmp"; return 1; }
  if ! sed -E \
    -e 's#^LIX_INSTALLER_X86_64_LINUX_SHA256="[0-9a-f]+"#LIX_INSTALLER_X86_64_LINUX_SHA256="'"$linux_hash"'"#' \
    -e 's#^LIX_INSTALLER_AARCH64_DARWIN_SHA256="[0-9a-f]+"#LIX_INSTALLER_AARCH64_DARWIN_SHA256="'"$darwin_hash"'"#' \
    "$packages_file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! grep -qxF "LIX_INSTALLER_X86_64_LINUX_SHA256=\"$linux_hash\"" "$tmp" \
    || ! grep -qxF "LIX_INSTALLER_AARCH64_DARWIN_SHA256=\"$darwin_hash\"" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$packages_file" || { rm -f "$tmp"; return 1; }
}

function _update_lix_installer_pins {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Lix installer checksums from official binaries"
    return
  fi

  local tmp_dir linux_file darwin_file linux_hash darwin_hash
  tmp_dir="$(mktemp -d)" || fail "Failed to create Lix installer temp directory"
  linux_file="$tmp_dir/lix-installer-x86_64-linux"
  darwin_file="$tmp_dir/lix-installer-aarch64-darwin"
  if ! _download_lix_installer x86_64-linux "$linux_file" \
    || ! _download_lix_installer aarch64-darwin "$darwin_file"; then
    rm -rf "$tmp_dir"
    fail "Failed to download Lix installers"
  fi
  if ! linux_hash="$(_file_sha256 "$linux_file")" \
    || ! darwin_hash="$(_file_sha256 "$darwin_file")"; then
    rm -rf "$tmp_dir"
    fail "Failed to hash Lix installers"
  fi
  if [[ ! "$linux_hash" =~ ^[0-9a-f]{64}$ || ! "$darwin_hash" =~ ^[0-9a-f]{64}$ ]]; then
    rm -rf "$tmp_dir"
    fail "Invalid Lix installer checksum"
  fi
  if ! _write_lix_installer_pins "$linux_hash" "$darwin_hash"; then
    rm -rf "$tmp_dir"
    fail "Failed to update Lix installer checksums"
  fi
  rm -rf "$tmp_dir"
}

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

function _codex_windows_release_hashes {
  local tag metadata x64_digest arm64_digest
  tag="$1"
  metadata="$(curl -fsSL \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: dotfiles' \
    "https://api.github.com/repos/openai/codex/releases/tags/$tag")" \
    || fail "Failed to read Codex Windows release metadata"
  x64_digest="$(jq -r '.assets[] | select(.name == "codex-package-x86_64-pc-windows-msvc.tar.gz") | .digest // empty' <<< "$metadata")"
  arm64_digest="$(jq -r '.assets[] | select(.name == "codex-package-aarch64-pc-windows-msvc.tar.gz") | .digest // empty' <<< "$metadata")"
  [[ "$x64_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Invalid Codex Windows x64 checksum"
  [[ "$arm64_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "Invalid Codex Windows ARM64 checksum"
  printf '%s\n%s\n' "${x64_digest#sha256:}" "${arm64_digest#sha256:}"
}

function _write_codex_release_package {
  local tag linux_hash darwin_hash windows_x64_hash windows_arm64_hash version package_file tmp
  tag="$1"
  linux_hash="$2"
  darwin_hash="$3"
  windows_x64_hash="$4"
  windows_arm64_hash="$5"
  version="${tag#rust-v}"
  package_file="$DOTFILES_DIR/packages/codex-release.json"
  [[ -f "$package_file" ]] || fail "Missing Codex pin file: $package_file"

  tmp="$(mktemp "${package_file}.tmp.XXXXXX")" || fail "Failed to create Codex pin temp file"
  if ! jq -n \
    --arg version "$version" \
    --arg linuxHash "$linux_hash" \
    --arg darwinHash "$darwin_hash" \
    --arg windowsX64 "$windows_x64_hash" \
    --arg windowsArm64 "$windows_arm64_hash" \
    '{version: $version, linuxHash: $linuxHash, darwinHash: $darwinHash, windows: {x86_64: $windowsX64, aarch64: $windowsArm64}}' > "$tmp" \
    || ! chmod 644 "$tmp" \
    || ! mv "$tmp" "$package_file"; then
    rm -f "$tmp"
    fail "Failed to update Codex pin file"
  fi
}

function _update_codex_release_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Codex package from the latest GitHub release"
    return
  fi

  local tag linux_hash darwin_hash windows_hashes windows_x64_hash windows_arm64_hash version package_file current_version
  package_file="$DOTFILES_DIR/packages/codex-release.json"
  [[ -f "$package_file" ]] || fail "Missing Codex pin file: $package_file"
  tag="$(_latest_codex_release_tag)"
  version="${tag#rust-v}"
  current_version="$(jq -r '.version // empty' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Codex package already at $tag"
    return
  fi

  info "Updating Codex package to $tag..."
  _ensure_nix
  linux_hash="$(_prefetch_codex_release_hash "$tag" linux)"
  darwin_hash="$(_prefetch_codex_release_hash "$tag" darwin)"
  windows_hashes="$(_codex_windows_release_hashes "$tag")" \
    || fail "Failed to resolve Codex Windows checksums"
  windows_x64_hash="$(sed -n '1p' <<< "$windows_hashes")"
  windows_arm64_hash="$(sed -n '2p' <<< "$windows_hashes")"
  _write_codex_release_package "$tag" "$linux_hash" "$darwin_hash" "$windows_x64_hash" "$windows_arm64_hash"
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

function _pi_archive_url {
  printf 'https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-%s.tgz\n' "$1"
}

function _prefetch_pi_src_hash {
  local version output hash
  version="$1"
  output="$(nix store prefetch-file --json --hash-type sha256 "$(_pi_archive_url "$version")")" \
    || fail "Failed to prefetch Pi archive"
  hash="$(jq -r '.hash // empty' <<< "$output")"
  [[ -n "$hash" ]] || fail "Failed to parse Pi archive hash"
  printf '%s\n' "$hash"
}

function _download_pi_package_lock {
  local version lock_file tmp_dir tarball key package package_version integrity next
  version="$1"
  lock_file="$2"
  tmp_dir="$(mktemp -d)" || fail "Failed to create temp dir"
  tarball="$tmp_dir/pi.tgz"
  curl -fsSL "$(_pi_archive_url "$version")" -o "$tarball" \
    || { rm -rf "$tmp_dir"; fail "Failed to download Pi archive"; }
  tar -xOzf "$tarball" package/npm-shrinkwrap.json > "$lock_file" \
    || { rm -rf "$tmp_dir"; fail "Failed to extract Pi package lock"; }
  rm -rf "$tmp_dir"

  while IFS=$'\t' read -r key package package_version; do
    integrity="$(curl -fsSL "https://registry.npmjs.org/$package/$package_version" | jq -r '.dist.integrity // empty')" \
      || fail "Failed to fetch $package integrity"
    [[ -n "$integrity" ]] || fail "Failed to parse $package integrity"
    next="$(mktemp)" || fail "Failed to create temp file"
    cp -p "$lock_file" "$next" \
      && jq --arg key "$key" --arg integrity "$integrity" '.packages[$key].integrity = $integrity' "$lock_file" > "$next" \
      && mv "$next" "$lock_file" \
      || { rm -f "$next"; fail "Failed to add $package integrity to Pi package lock"; }
  done < <(jq -r '.packages | to_entries[] | select(.value.resolved and (.value.integrity | not)) | [.key, (.key | sub("^node_modules/"; "")), .value.version] | @tsv' "$lock_file")
}

function _prefetch_pi_npm_deps_hash {
  nix shell nixpkgs#prefetch-npm-deps -c prefetch-npm-deps "$1" \
    || fail "Failed to prefetch Pi npm deps"
}

function _write_pi_package {
  local version src_hash deps_hash package_file output_file tmp
  version="$1"
  src_hash="$2"
  deps_hash="$3"
  package_file="$DOTFILES_DIR/packages/pi-agent.nix"
  output_file="${4:-$package_file}"
  [[ -f "$package_file" ]] || fail "Missing Pi package file: $package_file"
  tmp="$output_file"
  [[ "$output_file" != "$package_file" ]] || tmp="$(mktemp)"

  sed -E \
    -e 's#version = "[^"]+";#version = "'"$version"'";#' \
    -e 's#^([[:space:]]*hash = ")[^"]+(";)$#\1'"$src_hash"'\2#' \
    -e 's#npmDepsHash = "[^"]+";#npmDepsHash = "'"$deps_hash"'";#' \
    "$package_file" > "$tmp" \
    || fail "Failed to update Pi package file"
  [[ "$tmp" == "$output_file" ]] || mv "$tmp" "$package_file"
}

function _validate_release_files {
  local label="$1" package_file="$2" lock_file="$3" version="$4" src_hash="$5" deps_hash="$6"
  nix-instantiate --parse "$package_file" >/dev/null \
    || fail "Failed to parse staged $label package"
  jq empty "$lock_file" \
    || fail "Failed to parse staged $label package lock"
  grep -qF "version = \"$version\";" "$package_file" \
    && grep -qF "hash = \"$src_hash\";" "$package_file" \
    && grep -qF "npmDepsHash = \"$deps_hash\";" "$package_file" \
    || fail "Staged $label package does not contain expected pins"
}

function _install_release_file_pair {
  local staged_package="$1" package_file="$2" staged_lock="$3" lock_file="$4" label="$5"
  local package_backup lock_backup
  package_backup="$(mktemp "${package_file}.backup.XXXXXX")" \
    || { rm -f "$staged_package" "$staged_lock"; fail "Failed to back up $label package"; }
  lock_backup="$(mktemp "${lock_file}.backup.XXXXXX")" \
    || { rm -f "$package_backup" "$staged_package" "$staged_lock"; fail "Failed to back up $label package lock"; }
  if ! cp -p "$package_file" "$package_backup" || ! cp -p "$lock_file" "$lock_backup"; then
    rm -f "$package_backup" "$lock_backup" "$staged_package" "$staged_lock"
    fail "Failed to back up $label files"
  fi

  if ! mv "$staged_package" "$package_file"; then
    rm -f "$package_backup" "$lock_backup" "$staged_package" "$staged_lock"
    fail "Failed to install $label files"
  fi
  if ! mv "$staged_lock" "$lock_file"; then
    rm -f "$staged_lock"
    if ! mv "$package_backup" "$package_file"; then
      rm -f "$lock_backup"
      fail "Failed to roll back $label package after install failure"
    fi
    rm -f "$lock_backup"
    fail "Failed to install $label files"
  fi
  rm -f "$package_backup" "$lock_backup" \
    || fail "Failed to clean up $label backups"
}

function _update_pi_release_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Pi package from the latest npm release"
    return
  fi

  local version current_version package_file lock_file
  package_file="$DOTFILES_DIR/packages/pi-agent.nix"
  lock_file="$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  [[ -f "$package_file" ]] || fail "Missing Pi package file: $package_file"
  [[ -f "$lock_file" ]] || fail "Missing Pi package lock: $lock_file"
  version="$(_latest_npm_package_version @earendil-works/pi-coding-agent)"
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Pi package already at $version"
    return
  fi

  info "Updating Pi package to $version..."
  _ensure_nix
  (
    local stage_dir tmp_package tmp_lock src_hash deps_hash
    stage_dir="$(mktemp -d "$DOTFILES_DIR/packages/.pi-update.XXXXXX")" \
      || fail "Failed to create Pi staging directory"
    trap 'rm -rf "$stage_dir"' EXIT
    tmp_package="$stage_dir/pi-agent.nix"
    tmp_lock="$stage_dir/pi-agent-npm-shrinkwrap.json"
    cp -p "$package_file" "$tmp_package" \
      && cp -p "$lock_file" "$tmp_lock" \
      || fail "Failed to stage Pi package files"

    src_hash="$(_prefetch_pi_src_hash "$version")"
    _download_pi_package_lock "$version" "$tmp_lock"
    deps_hash="$(_prefetch_pi_npm_deps_hash "$tmp_lock")"
    _write_pi_package "$version" "$src_hash" "$deps_hash" "$tmp_package"
    _validate_release_files "Pi" "$tmp_package" "$tmp_lock" "$version" "$src_hash" "$deps_hash"
    _install_release_file_pair "$tmp_package" "$package_file" "$tmp_lock" "$lock_file" "Pi package"
  )
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

  local version current_version package_file lock_file
  package_file="$DOTFILES_DIR/packages/obsidian-headless.nix"
  lock_file="$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"
  [[ -f "$package_file" ]] || fail "Missing Obsidian Headless package file: $package_file"
  [[ -f "$lock_file" ]] || fail "Missing Obsidian Headless package lock: $lock_file"
  version="$(_latest_npm_package_version obsidian-headless)"
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
  if [[ "$current_version" == "$version" ]]; then
    info "Obsidian Headless package already at $version"
    return
  fi

  info "Updating Obsidian Headless package to $version..."
  _ensure_nix
  (
    local stage_dir tmp_package tmp_lock src_hash deps_hash
    stage_dir="$(mktemp -d "$DOTFILES_DIR/packages/.obsidian-update.XXXXXX")" \
      || fail "Failed to create Obsidian Headless staging directory"
    trap 'rm -rf "$stage_dir"' EXIT
    tmp_package="$stage_dir/obsidian-headless.nix"
    tmp_lock="$stage_dir/obsidian-headless-package-lock.json"
    cp -p "$package_file" "$tmp_package" \
      && cp -p "$lock_file" "$tmp_lock" \
      || fail "Failed to stage Obsidian Headless package files"

    if ! src_hash="$(_prefetch_obsidian_headless_src_hash "$version")"; then
      printf '%s\n' "$src_hash"
      return 1
    fi
    _download_obsidian_headless_package_lock "$version" "$tmp_lock"
    if ! deps_hash="$(_prefetch_obsidian_headless_npm_deps_hash "$tmp_lock")"; then
      printf '%s\n' "$deps_hash"
      return 1
    fi
    _write_obsidian_headless_package "$version" "$src_hash" "$deps_hash" "$tmp_package"
    _validate_release_files "Obsidian Headless" "$tmp_package" "$tmp_lock" "$version" "$src_hash" "$deps_hash"
    _install_release_file_pair "$tmp_package" "$package_file" "$tmp_lock" "$lock_file" "Obsidian Headless package"
  )
}

function update_lix_installer_pins {
  info "Updating pinned Lix installer checksums..."
  _update_lix_installer_pins
  success "Finished updating pinned Lix installer checksums"
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
