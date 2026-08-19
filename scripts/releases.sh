#!/usr/bin/env bash
set -eo pipefail

# Release pin discovery, hashing, and tracked package updates.

function _sync_paths {
  python3 - "$@" <<'PY'
import errno
import os
import sys

fallback = False
for path in dict.fromkeys(sys.argv[1:]):
    fd = os.open(path, os.O_RDONLY)
    try:
        try:
            os.fsync(fd)
        except OSError as error:
            if os.path.isdir(path) and error.errno == errno.EINVAL:
                fallback = True
            else:
                raise
    finally:
        os.close(fd)
if fallback:
    os.sync()
PY
}

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
  _download_lix_installer x86_64-linux "$linux_file" &
  local linux_pid=$!
  _download_lix_installer aarch64-darwin "$darwin_file" &
  local darwin_pid=$!
  local download_failed=false
  wait "$linux_pid" || download_failed=true
  wait "$darwin_pid" || download_failed=true
  if [[ "$download_failed" == true ]]; then
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
  local hashes_dir linux_pid darwin_pid windows_pid failed=false windows_failed=false
  hashes_dir="$(mktemp -d)" || fail "Failed to create Codex hash temp directory"
  _prefetch_codex_release_hash "$tag" linux > "$hashes_dir/linux" & linux_pid=$!
  _prefetch_codex_release_hash "$tag" darwin > "$hashes_dir/darwin" & darwin_pid=$!
  _codex_windows_release_hashes "$tag" > "$hashes_dir/windows" & windows_pid=$!
  wait "$linux_pid" || failed=true
  wait "$darwin_pid" || failed=true
  wait "$windows_pid" || windows_failed=true
  if [[ "$failed" == true || "$windows_failed" == true ]]; then
    rm -rf "$hashes_dir"
    [[ "$windows_failed" == false ]] || fail "Failed to resolve Codex Windows checksums"
    fail "Failed to resolve Codex release checksums"
  fi
  linux_hash="$(<"$hashes_dir/linux")"
  darwin_hash="$(<"$hashes_dir/darwin")"
  windows_hashes="$(<"$hashes_dir/windows")"
  rm -rf "$hashes_dir"
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
  nix run "path:$DOTFILES_DIR#prefetch-npm-deps" -- "$1" \
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

function _release_process_start {
  local pid="$1" stat rest
  if [[ -r "/proc/$pid/stat" ]]; then
    stat="$(<"/proc/$pid/stat")"
    rest="${stat##*) }"
    awk '{print "proc:" $20}' <<< "$rest"
  else
    LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null | awk '{$1=$1; print "ps:" $0}'
  fi
}

function _release_owner_identity {
  local pid="$1" start
  start="$(_release_process_start "$pid")"
  [[ -n "$start" ]] || return 1
  printf '%s|%s\n' "$pid" "$start"
}

function _release_owner_identity_valid {
  local identity="$1" pid start
  pid="${identity%%|*}"
  start="${identity#*|}"
  [[ "$identity" == *"|"* && "$pid" =~ ^[0-9]+$ && -n "$start" ]]
}

function _release_owner_is_live {
  local identity="$1" pid start current_start
  _release_owner_identity_valid "$identity" || return 1
  pid="${identity%%|*}"
  start="${identity#*|}"
  kill -0 "$pid" 2>/dev/null || return 1
  current_start="$(_release_process_start "$pid")"
  [[ -n "$current_start" && "$current_start" == "$start" ]]
}

function _release_journal_owner_dir {
  local journal="$1" transaction_dir="$2" target owner_dir base
  if [[ -L "$journal" ]]; then
    target="$(readlink "$journal")"
    base="$(basename "$transaction_dir")"
    [[ "$target" != */* && "$target" == "$base.owner."* ]] || return 1
    owner_dir="$(dirname "$transaction_dir")/$target"
    [[ -d "$owner_dir" && ! -L "$owner_dir" ]] || return 1
    printf '%s\n' "$owner_dir"
  elif [[ -d "$journal" ]]; then
    printf '%s\n' "$journal"
  else
    return 1
  fi
}

function _recover_release_transaction {
  local journal="$1" package_file="$2" lock_file="$3" transaction_dir="$4"
  local owner_dir state tmp_package tmp_lock
  owner_dir="$(_release_journal_owner_dir "$journal" "$transaction_dir")" || return 1
  state="$(cat "$owner_dir/state" 2>/dev/null || true)"
  if [[ "$state" == "prepared" ]]; then
    [[ -f "$owner_dir/package.backup" && -f "$owner_dir/lock.backup" ]] || return 1
    tmp_package="$(mktemp "${package_file}.recovery.XXXXXX")" || return 1
    tmp_lock="$(mktemp "${lock_file}.recovery.XXXXXX")" || { rm -f "$tmp_package"; return 1; }
    cp -p "$owner_dir/package.backup" "$tmp_package" \
      && cp -p "$owner_dir/lock.backup" "$tmp_lock" \
      && mv "$tmp_package" "$package_file" \
      && mv "$tmp_lock" "$lock_file" \
      && _sync_paths "$package_file" "$lock_file" "${package_file%/*}" "${lock_file%/*}" \
      || { rm -f "$tmp_package" "$tmp_lock"; return 1; }
  elif [[ -n "$state" ]]; then
    return 1
  fi
  rm -f "$owner_dir/state" "$owner_dir/state.tmp" && _sync_paths "$owner_dir" || return 1
  rm -f "$owner_dir/package.backup" "$owner_dir/lock.backup"
  rm -rf "$owner_dir/stage"
  _sync_paths "$owner_dir"
}

function _remove_release_journal {
  local journal="$1" transaction_dir="$2" owner_dir
  owner_dir="$(_release_journal_owner_dir "$journal" "$transaction_dir")" || return 1
  if [[ -L "$journal" ]]; then
    rm -f "$journal" && rm -rf "$owner_dir"
  else
    rm -rf "$journal"
  fi
}

function _release_transaction_pending {
  local transaction_dir="$1" journal
  [[ -e "$transaction_dir" || -L "$transaction_dir" ]] && return 0
  for journal in "${transaction_dir}.claim."*.journal; do
    [[ -d "$journal" || -L "$journal" ]] && return 0
  done
  return 1
}

function _cleanup_orphaned_release_claims {
  local transaction_dir="$1" claim owner
  for claim in "${transaction_dir}.claim."*; do
    [[ -f "$claim" && ! -e "$claim.journal" && ! -L "$claim.journal" ]] || continue
    owner="$(cat "$claim" 2>/dev/null || true)"
    _release_owner_is_live "$owner" || rm -f "$claim"
  done
}

function _recover_orphaned_release_journal {
  local transaction_dir="$1" package_file="$2" lock_file="$3" label="$4" identity="$5"
  local journal="" candidate claim owner new_claim new_journal
  for candidate in "${transaction_dir}.claim."*.journal; do
    [[ -d "$candidate" || -L "$candidate" ]] || continue
    [[ -z "$journal" ]] || fail "Multiple interrupted $label recovery journals found"
    journal="$candidate"
  done
  [[ -n "$journal" ]] || return 0

  claim="${journal%.journal}"
  owner="$(cat "$claim" 2>/dev/null || true)"
  _release_owner_identity_valid "$owner" \
    || fail "$label recovery journal owner is incomplete"
  _release_owner_is_live "$owner" \
    && fail "$label update recovery already running"

  new_claim="$(mktemp "${transaction_dir}.claim.XXXXXX")" \
    || fail "Failed to prepare interrupted $label recovery claim"
  printf '%s\n' "$identity" > "$new_claim" \
    && _sync_paths "$new_claim" "${new_claim%/*}" \
    || { rm -f "$new_claim"; fail "Failed to prepare interrupted $label recovery claim"; }
  new_journal="$new_claim.journal"
  mv "$journal" "$new_journal" 2>/dev/null \
    || { rm -f "$new_claim"; fail "$label recovery journal changed"; }
  rm -f "$claim"
  _recover_release_transaction "$new_journal" "$package_file" "$lock_file" "$transaction_dir" \
    || fail "Failed to recover interrupted $label update"
  _remove_release_journal "$new_journal" "$transaction_dir" \
    || fail "Failed to clean recovered $label journal"
  rm -f "$new_claim"
}

function _acquire_release_transaction {
  local transaction_dir="$1" package_file="$2" lock_file="$3" label="$4"
  local pid identity owner claim journal owner_dir
  pid="${BASHPID:-$$}"
  identity="$(_release_owner_identity "$pid")" || fail "Failed to identify $label update process"
  _cleanup_orphaned_release_claims "$transaction_dir"
  _recover_orphaned_release_journal "$transaction_dir" "$package_file" "$lock_file" "$label" "$identity"

  if [[ ! -e "$transaction_dir" && ! -L "$transaction_dir" ]]; then
    owner_dir="$(mktemp -d "${transaction_dir}.owner.XXXXXX")" \
      || fail "Failed to create $label update owner"
    printf '%s\n' "$identity" > "$owner_dir/pid" \
      && _sync_paths "$owner_dir/pid" "$owner_dir" \
      || { rm -rf "$owner_dir"; fail "Failed to initialize $label update lock"; }
    ln -s "$(basename "$owner_dir")" "$transaction_dir" 2>/dev/null \
      || { rm -rf "$owner_dir"; fail "Failed to publish $label update lock"; }
    _recover_orphaned_release_journal "$transaction_dir" "$package_file" "$lock_file" "$label" "$identity"
    return
  fi

  owner_dir="$(_release_journal_owner_dir "$transaction_dir" "$transaction_dir")" \
    || fail "$label update owner directory is invalid"
  owner="$(cat "$owner_dir/pid" 2>/dev/null || true)"
  _release_owner_identity_valid "$owner" \
    || fail "$label update lock owner is incomplete"
  _release_owner_is_live "$owner" \
    && fail "$label update already running"

  claim="$(mktemp "${transaction_dir}.claim.XXXXXX")" \
    || fail "Failed to prepare interrupted $label recovery claim"
  printf '%s\n' "$identity" > "$claim" \
    && _sync_paths "$claim" "${claim%/*}" \
    || { rm -f "$claim"; fail "Failed to prepare interrupted $label recovery claim"; }
  journal="$claim.journal"
  mv "$transaction_dir" "$journal" 2>/dev/null \
    || { rm -f "$claim"; fail "$label update lock changed"; }
  _recover_release_transaction "$journal" "$package_file" "$lock_file" "$transaction_dir" \
    || fail "Failed to recover interrupted $label update"
  _remove_release_journal "$journal" "$transaction_dir" \
    || fail "Failed to clean recovered $label journal"
  rm -f "$claim"
  _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "$label"
}

function _release_release_transaction {
  local transaction_dir="$1" pid identity owner state owner_dir
  [[ -d "$transaction_dir" || -L "$transaction_dir" ]] || return 0
  pid="${BASHPID:-$$}"
  identity="$(_release_owner_identity "$pid")" || return 0
  owner_dir="$(_release_journal_owner_dir "$transaction_dir" "$transaction_dir")" || return 0
  owner="$(cat "$owner_dir/pid" 2>/dev/null || true)"
  state="$(cat "$owner_dir/state" 2>/dev/null || true)"
  [[ "$owner" == "$identity" && "$state" != "prepared" ]] || return 0
  _remove_release_journal "$transaction_dir" "$transaction_dir"
}

function _install_release_file_pair {
  local staged_package="$1" package_file="$2" staged_lock="$3" lock_file="$4" label="$5" transaction_dir="$6"
  local package_backup="$transaction_dir/package.backup" lock_backup="$transaction_dir/lock.backup"
  if ! cp -p "$package_file" "$package_backup" \
    || ! cp -p "$lock_file" "$lock_backup" \
    || ! cmp -s "$package_file" "$package_backup" \
    || ! cmp -s "$lock_file" "$lock_backup"; then
    rm -f "$package_backup" "$lock_backup" "$staged_package" "$staged_lock"
    fail "Failed to back up $label files"
  fi
  _sync_paths "$package_backup" "$lock_backup" "$transaction_dir" \
    || fail "Failed to persist $label backups"
  printf 'prepared\n' > "$transaction_dir/state.tmp" \
    && _sync_paths "$transaction_dir/state.tmp" "$transaction_dir" \
    && mv "$transaction_dir/state.tmp" "$transaction_dir/state" \
    && _sync_paths "$transaction_dir/state" "$transaction_dir" \
    || fail "Failed to prepare $label transaction journal"

  if ! mv "$staged_package" "$package_file" || ! mv "$staged_lock" "$lock_file" \
    || ! _sync_paths "$package_file" "$lock_file" "${package_file%/*}" "${lock_file%/*}"; then
    rm -f "$staged_package" "$staged_lock"
    _recover_release_transaction "$transaction_dir" "$package_file" "$lock_file" "$transaction_dir" \
      || fail "Failed to recover $label after install failure"
    fail "Failed to install $label files"
  fi
  rm -f "$transaction_dir/state" \
    && _sync_paths "$transaction_dir" \
    || fail "Failed to commit $label transaction journal"
  rm -f "$package_backup" "$lock_backup" \
    || fail "Failed to clean up $label backups"
}

function _update_pi_release_package {
  if [[ "$DRY" == "true" ]]; then
    info "Would update Pi package from the latest npm release"
    return
  fi

  local package_file="$DOTFILES_DIR/packages/pi-agent.nix"
  local lock_file="$DOTFILES_DIR/packages/pi-agent-npm-shrinkwrap.json"
  [[ -f "$package_file" ]] || fail "Missing Pi package file: $package_file"
  [[ -f "$lock_file" ]] || fail "Missing Pi package lock: $lock_file"
  (
    local transaction_dir="$DOTFILES_DIR/packages/.pi-update.transaction"
    local stage_dir="" version current_version tmp_package tmp_lock src_hash deps_hash
    trap '[[ -z "$stage_dir" ]] || rm -rf "$stage_dir"; _release_release_transaction "$transaction_dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "Pi package"

    version="$(_latest_npm_package_version @earendil-works/pi-coding-agent)"
    current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
    if [[ "$current_version" == "$version" ]]; then
      info "Pi package already at $version"
      return
    fi

    info "Updating Pi package to $version..."
    _ensure_nix
    stage_dir="$transaction_dir/stage"
    mkdir "$stage_dir" || fail "Failed to create Pi staging directory"
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
    _install_release_file_pair "$tmp_package" "$package_file" "$tmp_lock" "$lock_file" "Pi package" "$transaction_dir"
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
  if ! tar -xOzf "$tarball" package/package-lock.json > "$lock_file" 2>/dev/null; then
    tar -xOzf "$tarball" package/package.json > "$tmp_dir/package.json" \
      || { rm -rf "$tmp_dir"; fail "Failed to extract Obsidian Headless package metadata"; }
    (
      cd "$tmp_dir" \
        && nix develop "path:$DOTFILES_DIR" -c npm install --package-lock-only --ignore-scripts --no-audit --omit=dev >/dev/null
    ) || { rm -rf "$tmp_dir"; fail "Failed to generate Obsidian Headless package lock"; }
    cp "$tmp_dir/package-lock.json" "$lock_file" \
      || { rm -rf "$tmp_dir"; fail "Failed to stage Obsidian Headless package lock"; }
  fi
  rm -rf "$tmp_dir"
}

function _prefetch_obsidian_headless_npm_deps_hash {
  local lock_file
  lock_file="${1:-$DOTFILES_DIR/packages/obsidian-headless-package-lock.json}"
  nix run "path:$DOTFILES_DIR#prefetch-npm-deps" -- "$lock_file" \
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

  local package_file="$DOTFILES_DIR/packages/obsidian-headless.nix"
  local lock_file="$DOTFILES_DIR/packages/obsidian-headless-package-lock.json"
  [[ -f "$package_file" ]] || fail "Missing Obsidian Headless package file: $package_file"
  [[ -f "$lock_file" ]] || fail "Missing Obsidian Headless package lock: $lock_file"
  (
    local transaction_dir="$DOTFILES_DIR/packages/.obsidian-update.transaction"
    local stage_dir="" version current_version tmp_package tmp_lock src_hash deps_hash
    trap '[[ -z "$stage_dir" ]] || rm -rf "$stage_dir"; _release_release_transaction "$transaction_dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _acquire_release_transaction "$transaction_dir" "$package_file" "$lock_file" "Obsidian Headless package"

    version="$(_latest_npm_package_version obsidian-headless)"
    current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";.*/\1/p' "$package_file")"
    if [[ "$current_version" == "$version" ]]; then
      info "Obsidian Headless package already at $version"
      return
    fi

    info "Updating Obsidian Headless package to $version..."
    _ensure_nix
    stage_dir="$transaction_dir/stage"
    mkdir "$stage_dir" || fail "Failed to create Obsidian Headless staging directory"
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
    _install_release_file_pair "$tmp_package" "$package_file" "$tmp_lock" "$lock_file" "Obsidian Headless package" "$transaction_dir"
  )
}

function _update_all_dependency_pins {
  _update_lix_installer_pins
  _update_codex_release_package
  _update_pi_release_package
  _update_obsidian_headless_package
  _run_python_pin_batch \
    codebase-memory "codebase-memory release" \
    fff "FFF release" \
    pi-extensions "Pi extension closure" \
    webcord "WebCord release" \
    anki-zoom "Anki Zoom add-on" \
    firacode "FiraCode Nerd Font" \
    skills "vendored agent skills" \
    neovim "Neovim plugins"
}

function _refresh_all_dependency_set {
  _update_flake_inputs
  _update_all_dependency_pins
}

function _refresh_ai_dependency_set {
  _update_codex_release_package
  _update_pi_release_package
}

function _dependency_git_repository {
  [[ "$(git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]]
}

function _dependency_update_marker {
  local scope="${1:-full}" git_dir marker
  case "$scope" in
    full) marker=dotfile-dependency-update ;;
    ai) marker=dotfile-ai-update ;;
    *) return 1 ;;
  esac
  git_dir="$(git -C "$DOTFILES_DIR" rev-parse --absolute-git-dir)" || return 1
  printf '%s/%s\n' "$git_dir" "$marker"
}

function _dependency_git_common_dir {
  local common
  common="$(git -C "$DOTFILES_DIR" rev-parse --git-common-dir)" || return 1
  if [[ "$common" != /* ]]; then
    common="$(cd "$DOTFILES_DIR/$common" && pwd -P)" || return 1
  fi
  printf '%s\n' "$common"
}

function _acquire_dependency_update_lock {
  local common lock identity owner owner_dir claim journal pid="${BASHPID:-$$}"
  common="$(_dependency_git_common_dir)" || return 1
  lock="$common/dotfile-dependency-update.lock"
  identity="$(_release_owner_identity "$pid")" || return 1

  if [[ ! -e "$lock" && ! -L "$lock" ]]; then
    owner_dir="$(mktemp -d "${lock}.owner.XXXXXX")" || return 1
    printf '%s\n' "$identity" > "$owner_dir/pid" \
      || { rm -rf "$owner_dir"; return 1; }
    if ln -s "$(basename "$owner_dir")" "$lock" 2>/dev/null; then
      DEPENDENCY_UPDATE_LOCK="$lock"
      return 0
    fi
    rm -rf "$owner_dir"
  fi

  owner_dir="$(_release_journal_owner_dir "$lock" "$lock")" || return 1
  owner="$(cat "$owner_dir/pid" 2>/dev/null)" || return 1
  _release_owner_identity_valid "$owner" || return 1
  _release_owner_is_live "$owner" && return 1

  claim="$(mktemp "${lock}.claim.XXXXXX")" || return 1
  printf '%s\n' "$identity" > "$claim" || { rm -f "$claim"; return 1; }
  journal="$claim.journal"
  mv "$lock" "$journal" 2>/dev/null || { rm -f "$claim"; return 1; }
  owner_dir="$(_release_journal_owner_dir "$journal" "$lock")" \
    || { rm -f "$journal" "$claim"; return 1; }
  rm -f "$journal" "$claim"
  rm -rf "$owner_dir"
  _acquire_dependency_update_lock
}

function _release_dependency_update_lock {
  local lock="${1:-${DEPENDENCY_UPDATE_LOCK:-}}" owner identity owner_dir pid="${BASHPID:-$$}"
  [[ -n "$lock" && -L "$lock" ]] || return 0
  owner_dir="$(_release_journal_owner_dir "$lock" "$lock")" || return 1
  owner="$(cat "$owner_dir/pid" 2>/dev/null)" || return 1
  identity="$(_release_owner_identity "$pid")" || return 1
  [[ "$owner" == "$identity" ]] || return 1
  rm -f "$lock" || return 1
  rm -rf "$owner_dir"
}

function _begin_dependency_update {
  local git_dir common
  git_dir="$(git -C "$DOTFILES_DIR" rev-parse --absolute-git-dir)" || return 1
  common="$(_dependency_git_common_dir)" || return 1
  [[ "$git_dir" == "$common" ]] || return 1
  _acquire_dependency_update_lock || return 1
  trap '_release_dependency_update_lock "${DEPENDENCY_UPDATE_LOCK:-}"' EXIT
  trap '_release_dependency_update_lock "${DEPENDENCY_UPDATE_LOCK:-}"; exit 1' HUP INT TERM
}

function _end_dependency_update {
  _release_dependency_update_lock "${DEPENDENCY_UPDATE_LOCK:-}" || return 1
  DEPENDENCY_UPDATE_LOCK=
  trap - EXIT HUP INT TERM
}

function _dependency_update_fingerprint {
  local tmp untracked_list head untracked fingerprint status=0
  tmp="$(mktemp)" || return 1
  untracked_list="$(mktemp)" || { rm -f "$tmp"; return 1; }
  head="$(git -C "$DOTFILES_DIR" rev-parse HEAD)" \
    || { rm -f "$tmp" "$untracked_list"; return 1; }
  git -C "$DOTFILES_DIR" ls-files --others --exclude-standard -z > "$untracked_list" \
    || { rm -f "$tmp" "$untracked_list"; return 1; }
  (
    printf 'head:%s\n' "$head"
    git -C "$DOTFILES_DIR" diff --binary HEAD -- || exit 1
    while IFS= read -r -d '' untracked; do
      printf 'untracked:%s:' "$untracked"
      _file_sha256 "$DOTFILES_DIR/$untracked" || exit 1
    done < "$untracked_list"
  ) > "$tmp" || status=$?
  if (( status != 0 )); then
    rm -f "$tmp" "$untracked_list"
    return "$status"
  fi
  fingerprint="$(_file_sha256 "$tmp")" \
    || { rm -f "$tmp" "$untracked_list"; return 1; }
  rm -f "$tmp" "$untracked_list"
  printf '%s\n' "$fingerprint"
}

function _dependency_update_pending {
  local scope="${1:-full}" marker status
  if ! _dependency_git_repository; then
    [[ ! -e "$DOTFILES_DIR/.git" ]] || fail "Failed to inspect dependency repository"
    return 1
  fi
  marker="$(_dependency_update_marker "$scope")" || return 1
  [[ -f "$marker" ]] || return 1
  status="$(git -C "$DOTFILES_DIR" status --porcelain)" \
    || fail "Failed to inspect dependency repository"
  if [[ -z "$status" ]]; then
    rm -f "$marker" || fail "Failed to remove stale dependency update marker"
    return 1
  fi
}

function _dependency_update_markers_conflict {
  _dependency_update_pending full && _dependency_update_pending ai
}

function _write_dependency_update_marker {
  local scope="${1:-full}" expected="${2:-}" marker other_scope other_marker fingerprint
  _dependency_git_repository || return 1
  case "$scope" in
    full) other_scope=ai ;;
    ai) other_scope=full ;;
    *) return 1 ;;
  esac
  marker="$(_dependency_update_marker "$scope")" || return 1
  other_marker="$(_dependency_update_marker "$other_scope")" || return 1
  [[ ! -e "$other_marker" && -n "$expected" ]] || return 1
  fingerprint="$(_dependency_update_fingerprint)" || return 1
  [[ "$fingerprint" == "$expected" ]] || return 1
  printf '%s\n' "$fingerprint" > "$marker.tmp" \
    && mv "$marker.tmp" "$marker"
}

function _validate_pending_dependency_update {
  local scope="${1:-full}" marker expected actual
  marker="$(_dependency_update_marker "$scope")" || fail "Failed to find pending dependency update"
  expected="$(cat "$marker" 2>/dev/null || true)"
  actual="$(_dependency_update_fingerprint)" || fail "Failed to inspect pending dependency update"
  [[ -n "$expected" && "$expected" == "$actual" ]] \
    || fail "Pending dependency update changed; review or discard it before retrying"
}

function _refresh_dependency_set {
  local updater="${1:-_refresh_all_dependency_set}" source_dir="$DOTFILES_DIR" result status=0
  DEPENDENCY_UPDATE_FINGERPRINT=
  _dependency_git_repository || return 1
  result="$(mktemp)" || return 1

  (
    local worktree="" patch="" base_fingerprint="" fingerprint="" base expected actual
    _cleanup_dependency_refresh() {
      [[ -z "$worktree" ]] || git -C "$source_dir" worktree remove --force "$worktree" >/dev/null 2>&1 || true
      rm -f "$patch" "$base_fingerprint" "$fingerprint"
    }
    trap _cleanup_dependency_refresh EXIT
    trap 'exit 1' HUP INT TERM

    worktree="$(mktemp -d)" || exit 1
    rmdir "$worktree" || exit 1
    patch="$(mktemp)" || exit 1
    base_fingerprint="$(mktemp)" || exit 1
    fingerprint="$(mktemp)" || exit 1
    git -C "$source_dir" worktree add --quiet --detach "$worktree" HEAD || exit 1

    (
      export DOTFILES_DIR="$worktree"
      cd "$worktree" || exit 1
      _dependency_update_fingerprint > "$base_fingerprint" || exit 1
      "$updater" || exit 1
      _validate_dependency_update || exit 1
      _dependency_update_fingerprint > "$fingerprint" || exit 1
      git add -A || exit 1
      git diff --cached --binary HEAD -- > "$patch" || exit 1
    )

    local source_status
    source_status="$(git -C "$source_dir" status --porcelain)" || exit 1
    [[ -z "$source_status" ]] || exit 1
    base="$(<"$base_fingerprint")"
    actual="$(_dependency_update_fingerprint)" || exit 1
    [[ -n "$base" && "$actual" == "$base" ]] || exit 1
    if [[ -s "$patch" ]]; then
      git -C "$source_dir" apply --binary "$patch" || exit 1
    fi
    expected="$(<"$fingerprint")"
    actual="$(_dependency_update_fingerprint)" || exit 1
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
      [[ ! -s "$patch" ]] || git -C "$source_dir" apply --reverse --binary "$patch" >/dev/null 2>&1 || true
      exit 1
    fi
    printf '%s\n' "$expected" > "$result"
  ) || status=$?

  if (( status != 0 )); then
    rm -f "$result"
    return "$status"
  fi
  DEPENDENCY_UPDATE_FINGERPRINT="$(cat "$result")" \
    || { rm -f "$result"; return 1; }
  rm -f "$result"
  [[ -n "$DEPENDENCY_UPDATE_FINGERPRINT" ]] || return 1
}

function _finish_dependency_update {
  [[ "$DRY" == "true" ]] && return
  local scope="${1:-full}" marker
  _dependency_git_repository || return 0
  marker="$(_dependency_update_marker "$scope")" || return 1
  rm -f "$marker" "$marker.tmp"
}

function _publish_dependency_update {
  [[ "$DRY" == "true" ]] && return
  local scope="${1:-full}" status branch remote merge upstream ahead behind subject
  status="$(git -C "$DOTFILES_DIR" status --porcelain)" \
    || fail "Failed to inspect dependency repository"
  [[ -n "$status" ]] || return
  _validate_pending_dependency_update "$scope"
  branch="$(git -C "$DOTFILES_DIR" symbolic-ref --quiet --short HEAD)" \
    || fail "Dependency update requires a branch"
  remote="$(git -C "$DOTFILES_DIR" config --get "branch.$branch.remote")" \
    || fail "Dependency update branch has no upstream remote"
  merge="$(git -C "$DOTFILES_DIR" config --get "branch.$branch.merge")" \
    || fail "Dependency update branch has no upstream branch"
  upstream="${remote}/${merge#refs/heads/}"
  git -C "$DOTFILES_DIR" fetch "$remote" \
    || fail "Failed to fetch dependency update remote"
  ahead="$(git -C "$DOTFILES_DIR" rev-list --count "$upstream..HEAD")" \
    || fail "Failed to compare dependency update branch"
  [[ "$ahead" == 0 ]] \
    || fail "Dependency update branch has unpublished commits; push them before updating"

  subject="chore: update dependencies"
  [[ "$scope" != ai ]] || subject="chore: update AI dependencies"
  git -C "$DOTFILES_DIR" add -A \
    && git -C "$DOTFILES_DIR" commit -m "$subject" \
    || fail "Failed to commit dependency update"
  git -C "$DOTFILES_DIR" fetch "$remote" \
    || fail "Failed to refresh dependency update remote"
  behind="$(git -C "$DOTFILES_DIR" rev-list --count "HEAD..$upstream")" \
    || fail "Failed to compare dependency update branch"
  if (( behind > 0 )); then
    git -C "$DOTFILES_DIR" rebase "$upstream" \
      || fail "Dependency update rebase needs manual conflict resolution"
  fi
  git -C "$DOTFILES_DIR" push "$remote" "HEAD:${merge#refs/heads/}" \
    || fail "Failed to push dependency update"
}

function _require_clean_dependency_tree {
  [[ "$DRY" == "true" ]] && return
  _dependency_git_repository || fail "Dependency update requires a Git repository"
  local status
  status="$(git -C "$DOTFILES_DIR" status --porcelain)" \
    || fail "Failed to inspect dependency repository"
  [[ -z "$status" ]] || fail "Dependency update requires a clean repository"
}

function _validate_dependency_update {
  if [[ "$DRY" == "true" ]]; then
    info "Would run full dependency checks before activation"
    return
  fi
  "$DOTFILES_DIR/scripts/check.sh" || fail "Dependency checks failed; refusing activation"
}

function _approve_dependency_update {
  [[ "$DRY" == "true" ]] && return
  _dependency_git_repository || fail "Dependency update requires a Git repository"
  local status untracked untracked_list diff_status answer
  status="$(git -C "$DOTFILES_DIR" status --porcelain)" \
    || fail "Failed to inspect dependency repository"
  [[ -n "$status" ]] || return
  git -C "$DOTFILES_DIR" status --short || fail "Failed to show dependency status"
  git -C "$DOTFILES_DIR" diff -- || fail "Failed to show dependency diff"
  git -C "$DOTFILES_DIR" diff --cached -- || fail "Failed to show staged dependency diff"
  untracked_list="$(mktemp)" || fail "Failed to inspect untracked dependency files"
  git -C "$DOTFILES_DIR" ls-files --others --exclude-standard > "$untracked_list" \
    || { rm -f "$untracked_list"; fail "Failed to inspect untracked dependency files"; }
  while IFS= read -r untracked; do
    if git -C "$DOTFILES_DIR" diff --no-index -- /dev/null "$DOTFILES_DIR/$untracked"; then
      :
    else
      diff_status=$?
      if (( diff_status > 1 )); then
        rm -f "$untracked_list"
        fail "Failed to show untracked dependency diff"
      fi
    fi
  done < "$untracked_list"
  rm -f "$untracked_list"
  if [[ "$FORCE" == "true" ]]; then
    info "Activating reviewed dependency changes because --force was supplied"
    return
  fi
  [[ -t 0 ]] || fail "Dependency pins changed; review the diff, then rerun with --force to activate"
  printf '  [ ?? ] Activate these dependency changes? [y/N] ' >&2
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]] || fail "Dependency activation cancelled; changes remain for review"
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
