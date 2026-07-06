#!/usr/bin/env bash
# Language toolchain installers (Linux + macOS only).
# Sourced by `dotfile`. Requires utils.sh, platform.sh, packages.sh already
# sourced — the generic GitHub-release helpers (_install_from_github_release,
# _install_into_local, _assert_single_top_dir, _sha256, _strip_sha256_prefix,
# ensure_jq) live in packages.sh.
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

# Print the version embedded in a tool's ~/.local/bin/<name> symlink IF this
# script installed it (target must be ~/.local/<name>-<version>/<name>).
# Empty string for: no install, or a foreign install (system/brew/scoop).
# Shared by zig/odin/gleam — their layouts are identical modulo the name.
_local_installed_version() {
  local name="$1"
  local link="$HOME/.local/bin/$name"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  local prefix="$HOME/.local/${name}-" suffix="/$name"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#"$prefix"}"
      middle="${middle%"$suffix"}"
      # Reject a nested dir (slash left in the middle) — not our flat layout.
      case "$middle" in
        */*) return 0 ;;
      esac
      echo "$middle"
      ;;
  esac
}

# Re-run an installer, but only if this script previously installed the tool.
# Foreign installs (system/brew/scoop) are left alone.
_update_if_ours() {
  local name="$1" install_fn="$2"
  local current
  current="$(_local_installed_version "$name")"
  if _home_manager_manages_languages; then
    [[ -n "$current" ]] && info "$name is managed by Home Manager on $(detect_platform); skipping update"
    return 0
  fi
  [[ -n "$current" ]] && "$install_fn"
  return 0
}

# Map (uname -s, uname -m) to Zig's tarball arch slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
zig_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)                 echo "x86_64-linux" ;;
    Linux/aarch64|Linux/arm64)    echo "aarch64-linux" ;;
    Darwin/x86_64)                echo "x86_64-macos" ;;
    Darwin/arm64|Darwin/aarch64)  echo "aarch64-macos" ;;
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
    Linux/x86_64)                 echo "x86_64-unknown-linux-musl" ;;
    Linux/aarch64|Linux/arm64)    echo "aarch64-unknown-linux-musl" ;;
    Darwin/x86_64)                echo "x86_64-apple-darwin" ;;
    Darwin/arm64|Darwin/aarch64)  echo "aarch64-apple-darwin" ;;
    *) fail "Unsupported platform for gleam install: $os/$arch" ;;
  esac
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

# Install (or upgrade) Zig from the official community mirrors with full
# minisign signature verification + sha256 cross-check.
#
# Layout: extracts to ~/.local/zig-<version>/ and symlinks ~/.local/bin/zig.
# Skips if the target version is already installed (per _local_installed_version).
install_zig() {
  info "Installing Zig..."
  ensure_pkg minisign
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
  current="$(_local_installed_version zig)"
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
  # the arch portion when moving so _local_installed_version's parsing
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

update_zig() { _update_if_ours zig install_zig; }

_home_manager_manages_languages() {
  case "$(detect_platform)" in
    arch|debian|nixos|mac) return 0 ;;
    *) return 1 ;;
  esac
}

_install_or_skip_home_manager_language() {
  local label="$1" install_fn="$2"
  if _home_manager_manages_languages; then
    info "$label is managed by Home Manager on $(detect_platform); skipping"
    return 0
  fi
  "$install_fn"
}

# Umbrella: install all languages, or just one if specified.
# Usage: install_languages [LANG]
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") _install_or_skip_home_manager_language Zig install_zig; _install_or_skip_home_manager_language Odin install_odin; _install_or_skip_home_manager_language Gleam install_gleam; install_jank ;;
    zig)    _install_or_skip_home_manager_language Zig install_zig ;;
    odin)   _install_or_skip_home_manager_language Odin install_odin ;;
    gleam)  _install_or_skip_home_manager_language Gleam install_gleam ;;
    jank)   install_jank ;;
    *)      fail "Unknown language: $target" ;;
  esac
}

# Map (uname -s, uname -m) to Odin's release-asset slug.
# Prints the slug on stdout. Fails if the platform is unsupported.
odin_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)                 echo "linux-amd64" ;;
    Linux/aarch64|Linux/arm64)    echo "linux-arm64" ;;
    Darwin/x86_64)                echo "macos-amd64" ;;
    Darwin/arm64|Darwin/aarch64)  echo "macos-arm64" ;;
    *) fail "Unsupported platform for odin install: $os/$arch" ;;
  esac
}

# Print the JSON body of the latest Odin release from the GitHub API.
odin_latest_release() {
  http_get_retry "https://api.github.com/repos/odin-lang/Odin/releases/latest" \
    || fail "Failed to fetch Odin releases/latest"
}

# Install (or upgrade) Odin from the official GitHub releases.
#
# Layout: extracts to ~/.local/odin-<tag>/ and symlinks ~/.local/bin/odin.
# Skips if the target tag is already installed.
install_odin() {
  info "Installing Odin..."
  ensure_clang
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
  current="$(_local_installed_version odin)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Odin $tag"
    return 0
  fi

  local asset="odin-${triple}-${tag}.tar.gz"
  _install_from_github_release "Odin" "odin" "$release_json" "$tag" "$asset" "single-dir" "odin"
}

# Update Odin — but only if it was installed by this script.
update_odin() { _update_if_ours odin install_odin; }

# Print the JSON body of the latest Gleam release from the GitHub API.
gleam_latest_release() {
  http_get_retry "https://api.github.com/repos/gleam-lang/gleam/releases/latest" \
    || fail "Failed to fetch Gleam releases/latest"
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
      ensure_pkg clang
      ;;
  esac
}

# Install (or upgrade) Gleam from the official GitHub releases.
# Layout: extracts to ~/.local/gleam-<tag>/gleam and symlinks ~/.local/bin/gleam.
# Auto-installs the Erlang/OTP runtime (gleam compiles to BEAM). rebar3 is only
# needed by some hex deps, so it's left for the user to install on demand.
install_gleam() {
  info "Installing Gleam..."
  ensure_jq
  ensure_pkg erl erlang "Erlang/OTP"

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
  current="$(_local_installed_version gleam)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Gleam $tag"
    return 0
  fi

  local asset="gleam-${tag}-${triple}.tar.gz"
  _install_from_github_release "Gleam" "gleam" "$release_json" "$tag" "$asset" "flat-binary" "gleam"
}

# Update Gleam — but only if it was installed by this script.
update_gleam() { _update_if_ours gleam install_gleam; }

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
# Lenient on unsupported platforms: `dotfile languages` skips, direct
# `install_jank` reports the unsupported platform and returns success.

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
      command -v yay >/dev/null 2>&1 || fail "yay required to install jank-bin on Arch"
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
