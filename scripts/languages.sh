#!/bin/bash
# Language toolchain installers (Linux + macOS only).
# Sourced by `dotfile`. Requires utils.sh, platform.sh, packages.sh already sourced.
set -eo pipefail

# Zig signing public key. Pinned to defend against MITM during install.
# Source: https://ziglang.org/download/  Copied: 2026-04-17
#
# Rotation is rare but happens. Suspect it when install_zig fails at
# minisign verification on a known-good network (the failure message
# will mention "Signature verification failed"). To update:
#   1. Visit https://ziglang.org/download/ and copy the new minisign key.
#   2. Replace ZIG_PUBKEY below.
#   3. Update the "Copied:" date in this comment.
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

# Assert that exactly one top-level directory exists under <extract_dir>.
# Prints the resolved path on stdout. Fails with $display_name in the message
# when the count is not 1. Uses a portable bash 3.2 loop (no mapfile/readarray).
_assert_single_top_dir() {
  local extract_dir="$1" display_name="$2"
  local extracted="" extra_dir extracted_count=0
  while IFS= read -r extra_dir; do
    extracted_count=$((extracted_count + 1))
    extracted="$extra_dir"
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
  if [[ "$extracted_count" -ne 1 ]]; then
    fail "$display_name tarball extracted to unexpected layout ($extracted_count top-level dirs)"
  fi
  echo "$extracted"
}

# Move <extracted_path> to ~/.local/<lc_name>-<version>/, symlink the binary
# into ~/.local/bin/, and remove any prior ~/.local/<lc_name>-* siblings.
# Idempotent — safe to call repeatedly.
_install_into_local() {
  local lc_name="$1" version="$2" bin_name="$3" extracted_path="$4"
  local target_dir="$HOME/.local/${lc_name}-${version}"

  rm -rf "$target_dir"
  mv "$extracted_path" "$target_dir" || fail "Failed to move $lc_name into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/$bin_name" "$HOME/.local/bin/$bin_name" \
    || fail "Failed to create ~/.local/bin/$bin_name symlink"

  # Clean up old versions (any ~/.local/<lc_name>-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/"${lc_name}"-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done
}

# Strip the "sha256:" prefix from a GitHub release digest string.
# Fails loudly if the prefix is absent — the caller MUST NOT silently
# compare against a value of unknown algorithm.
_strip_sha256_prefix() {
  local digest="$1"
  local stripped="${digest#sha256:}"
  if [[ "$stripped" == "$digest" ]]; then
    fail "Unexpected digest format: $digest"
  fi
  echo "$stripped"
}

# Install a binary from a GitHub release tarball. Used by install_odin and
# install_gleam (zig has its own flow with mirror retry + minisign).
#
# Args (positional):
#   $1 display_name  e.g. "Odin"
#   $2 lc_name       e.g. "odin"
#   $3 release_json  body of GitHub releases/latest
#   $4 tag           already-extracted tag_name (e.g. "v1.2.3")
#   $5 asset         asset filename inside the release (e.g. "odin-...-v1.2.3.tar.gz")
#   $6 layout        "single-dir" (one top-level dir) or "flat-binary" (binary at root)
#   $7 bin_name      binary name to symlink (e.g. "odin")
_install_from_github_release() {
  local display_name="$1" lc_name="$2" release_json="$3" tag="$4"
  local asset="$5" layout="$6" bin_name="$7"

  local digest
  digest="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // empty')"
  if [[ -z "$digest" ]]; then
    fail "Could not find digest for $asset in $display_name releases/latest"
  fi
  local expected_sha
  expected_sha="$(_strip_sha256_prefix "$digest")"

  local asset_url
  asset_url="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .browser_download_url // empty')"
  if [[ -z "$asset_url" ]]; then
    fail "Could not find download URL for $asset in $display_name releases/latest"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # EXIT covers fail()'s exit 1 path; RETURN covers normal returns. Without
  # EXIT, every fail() in this function would leak $tmpdir under /tmp.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT RETURN

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
    || fail "Failed to extract $display_name tarball"

  local extracted
  case "$layout" in
    single-dir)
      extracted="$(_assert_single_top_dir "$extract_dir" "$display_name")"
      ;;
    flat-binary)
      if [[ ! -f "$extract_dir/$bin_name" ]]; then
        fail "$display_name binary not found at top level of tarball"
      fi
      # Wrap the bare binary in a directory so _install_into_local can mv it.
      mkdir -p "$tmpdir/wrapped"
      mv "$extract_dir/$bin_name" "$tmpdir/wrapped/$bin_name"
      extracted="$tmpdir/wrapped"
      ;;
    *)
      fail "_install_from_github_release: unknown layout: $layout"
      ;;
  esac

  _install_into_local "$lc_name" "$tag" "$bin_name" "$extracted"

  success "Installed $display_name $tag"
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
  # EXIT covers fail()'s exit 1 path; RETURN covers normal returns. Without
  # EXIT, every fail() in this function would leak $tmpdir under /tmp.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT RETURN

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
  local extracted
  extracted=$(_assert_single_top_dir "$extract_dir" "Zig")

  _install_into_local "zig" "$version" "zig" "$extracted"

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
    all|"") install_zig; install_odin; install_gleam; install_jank ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    gleam)  install_gleam ;;
    jank)   install_jank ;;
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

  local current
  current="$(odin_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Odin $tag"
    return 0
  fi

  local asset="odin-${triple}-${tag}.tar.gz"
  _install_from_github_release "Odin" "odin" "$release_json" "$tag" "$asset" "single-dir" "odin"
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

# Print the currently-installed Gleam tag IF it was installed by this script.
# Returns empty for: no install, foreign install (system/brew/scoop).
# Detection rule: ~/.local/bin/gleam must be a symlink to ~/.local/gleam-<tag>/gleam.
gleam_current_installed_version() {
  local link="$HOME/.local/bin/gleam"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  local prefix="$HOME/.local/gleam-"
  local suffix="/gleam"
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

# Install Erlang/OTP via the platform package manager if missing. Required
# for Gleam runtime (gleam compiles to BEAM bytecode).
ensure_erlang() {
  if command -v erl >/dev/null 2>&1; then
    return 0
  fi
  info "Erlang/OTP not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y erlang || fail "Failed to install erlang" ;;
    arch)   sudo pacman -S --needed --noconfirm erlang || fail "Failed to install erlang" ;;
    mac)    brew install erlang || fail "Failed to install erlang" ;;
    *)      fail "Cannot install Erlang on this platform" ;;
  esac
  success "Installed Erlang/OTP"
}

# Install rebar3 via the platform package manager if missing. Optional Gleam
# build helper — only some projects need it, but cheap to install upfront.
ensure_rebar3() {
  if command -v rebar3 >/dev/null 2>&1; then
    return 0
  fi
  info "rebar3 not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y rebar3 || fail "Failed to install rebar3" ;;
    arch)   sudo pacman -S --needed --noconfirm rebar3 || fail "Failed to install rebar3" ;;
    mac)    brew install rebar3 || fail "Failed to install rebar3" ;;
    *)      fail "Cannot install rebar3 on this platform" ;;
  esac
  success "Installed rebar3"
}

# Ensure clang is available. Required at runtime by Odin to assemble/link
# generated C code (see https://odin-lang.org/docs/install/).
#
# macOS uses xcode-select -p instead of `command -v clang` because the
# /usr/bin/clang stub exists on PATH even when Command Line Tools aren't
# installed (the stub errors at invoke time). On macOS we don't auto-install
# CLT — `xcode-select --install` opens a blocking GUI prompt unsuitable for
# unattended `dotfile` runs — so we fail with instructions instead.
ensure_clang() {
  local platform
  platform="$(detect_platform)"

  case "$platform" in
    mac)
      xcode-select -p >/dev/null 2>&1 && return 0
      info "clang not found. Run \`xcode-select --install\` to install Apple Command Line Tools, then re-run."
      [[ "$DRY" == "true" ]] && return 0
      fail "clang not found. Run \`xcode-select --install\` to install Apple Command Line Tools, then re-run."
      ;;
    *)
      command -v clang >/dev/null 2>&1 && return 0
      info "clang not found; installing..."
      [[ "$DRY" == "true" ]] && return 0
      case "$platform" in
        debian) sudo apt install -y clang || fail "Failed to install clang" ;;
        arch)   sudo pacman -S --needed --noconfirm clang || fail "Failed to install clang" ;;
        *)      fail "Cannot install clang on this platform" ;;
      esac
      success "Installed clang"
      ;;
  esac
}

# Install (or upgrade) Gleam from the official GitHub releases.
# Layout: extracts to ~/.local/gleam-<tag>/gleam and symlinks ~/.local/bin/gleam.
# Auto-installs Erlang/OTP and rebar3 dependencies. Skips if at the target tag.
install_gleam() {
  info "Installing Gleam..."
  ensure_jq
  ensure_erlang
  ensure_rebar3

  local triple
  triple="$(gleam_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Gleam for $triple"
    success "Finished installing Gleam (dry run)"
    return 0
  fi

  local release_json
  release_json="$(gleam_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Gleam releases/latest"
  fi

  local current
  current="$(gleam_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Gleam $tag"
    return 0
  fi

  local asset="gleam-${tag}-${triple}.tar.gz"
  _install_from_github_release "Gleam" "gleam" "$release_json" "$tag" "$asset" "flat-binary" "gleam"
}

# Update Gleam — but only if it was installed by this script. Foreign installs
# (system, brew) are left alone.
update_gleam() {
  local current
  current="$(gleam_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_gleam
}

# Update every language that this script previously installed.
update_languages() {
  update_zig
  update_odin
  update_gleam
  update_jank
}

# Jank diverges from Zig/Odin/Gleam: installs via system PM (brew tap / AUR /
# PPA), not GitHub binary download. No SHA verify (PM provides trust), no
# ~/.local/jank-<v>/ layout, no precise version (jank has no --version flag).
# Lenient on unsupported platforms — see
# docs/superpowers/specs/2026-04-18-jank-language-install-design.md.

# Returns 0 if jank can be installed on this platform, non-zero otherwise.
# Does NOT call fail — caller decides whether to error or skip.
#
# Optional $1: override the /etc/os-release ID lookup (for tests).
jank_check_platform() {
  local id_override="${1:-}"
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    mac)
      [[ "$(uname -m)" == "arm64" ]] || return 1
      ;;
    arch) ;;  # supported
    debian)
      # detect_platform groups Ubuntu under "debian"; jank's PPA targets Ubuntu only.
      local ID="$id_override"
      if [[ -z "$ID" && -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
      fi
      [[ "${ID:-}" == "ubuntu" ]] || return 1
      ;;
    *) return 1 ;;
  esac
}

# Returns "installed" if jank is on PATH, empty otherwise.
# Jank has no --version flag, so we can't track precise versions like with
# Zig/Odin/Gleam. The string "installed" is a sentinel value.
jank_current_installed_version() {
  command -v jank >/dev/null 2>&1 && echo "installed"
}

# Idempotent jank PPA setup (Ubuntu only — caller enforces). One-time
# GPG key + sources.list addition + apt update. No-ops if jank.list exists.
_install_jank_ppa() {
  if [[ -f /etc/apt/sources.list.d/jank.list ]]; then
    return 0
  fi
  info "Setting up jank PPA..."
  sudo apt install -y curl gnupg || fail "Failed to install curl + gnupg"
  curl -sf "https://ppa.jank-lang.org/KEY.gpg" \
    | gpg --dearmor \
    | sudo tee /etc/apt/trusted.gpg.d/jank.gpg >/dev/null \
    || fail "Failed to import jank PPA signing key"
  sudo curl -sfo /etc/apt/sources.list.d/jank.list "https://ppa.jank-lang.org/jank.list" \
    || fail "Failed to fetch jank PPA sources list"
  sudo apt update || fail "Failed to apt update after jank PPA setup"
}

# Install Jank via the platform package manager.
# Lenient on unsupported platforms: visible skip + exit 0.
install_jank() {
  info "Installing Jank..."
  if ! jank_check_platform; then
    info "Skipping Jank: not supported on this platform — see https://book.jank-lang.org/getting-started/01-installation.html"
    success "Finished (skipped Jank)"
    return 0
  fi

  if [[ "$DRY" == "true" ]]; then
    info "Would install Jank via the platform package manager"
    success "Finished installing Jank (dry run)"
    return 0
  fi

  if [[ -n "$(jank_current_installed_version)" ]]; then
    success "Already installed Jank"
    return 0
  fi

  case "$(detect_platform)" in
    mac)
      brew install jank-lang/jank/jank || fail "Failed to install jank via brew"
      ;;
    arch)
      setup_yay  # idempotent helper from packages.sh
      yay -S --needed --noconfirm jank-bin || fail "Failed to install jank-bin via yay"
      ;;
    debian)  # Ubuntu only — jank_check_platform already enforced
      _install_jank_ppa || fail "Failed to set up jank PPA"
      sudo apt install -y jank || fail "Failed to install jank via apt"
      ;;
  esac
  success "Installed Jank"
}

# Update Jank via the platform package manager. Silent no-op on unsupported
# platforms or when jank isn't installed.
update_jank() {
  jank_check_platform || return 0
  [[ -z "$(jank_current_installed_version)" ]] && return 0
  info "Updating Jank..."
  if [[ "$DRY" == "true" ]]; then
    info "Would update Jank via the platform package manager"
    success "Finished updating Jank (dry run)"
    return 0
  fi
  case "$(detect_platform)" in
    mac)    brew update && brew reinstall jank-lang/jank/jank || fail "Failed to update jank via brew" ;;
    arch)   yay -Syy --noconfirm && yay -S --noconfirm jank-bin || fail "Failed to update jank via yay" ;;
    debian) sudo apt update && sudo apt reinstall -y jank || fail "Failed to update jank via apt" ;;
  esac
  success "Updated Jank"
}
