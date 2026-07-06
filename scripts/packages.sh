#!/usr/bin/env bash
set -eo pipefail

# Echo the log verb for a setup_* installer: "Updating" when $1 is "true"
# (i.e. --update mode), otherwise "Installing".
_action_verb() {
  if [[ "${1:-}" == "true" ]]; then echo "Updating"; else echo "Installing"; fi
}

# ---------------------------------------------------------------------------
# Generic GitHub-release download helpers
#
# Shared by the language installers in languages.sh (install_zig/odin/gleam).
# Defined in packages.sh
# because it is sourced before languages.sh, keeping the dependency direction
# one-way (languages.sh -> packages.sh).
# ---------------------------------------------------------------------------

# Portable sha256 of a file. Linux ships sha256sum; macOS ships shasum.
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
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

  mkdir -p "$HOME/.local"
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

  return 0
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
#   $8 asset_bin     (flat-binary only) name of the binary inside the tarball if
#                    it differs from bin_name (e.g. codex ships "codex-<triple>");
#                    defaults to bin_name.
_install_from_github_release() {
  local display_name="$1" lc_name="$2" release_json="$3" tag="$4"
  local asset="$5" layout="$6" bin_name="$7" asset_bin="${8:-$7}"

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
      if [[ ! -f "$extract_dir/$asset_bin" ]]; then
        fail "$display_name binary not found at top level of tarball"
      fi
      # Wrap the bare binary in a directory so _install_into_local can mv it,
      # renaming to bin_name when the tarball ships it under a different name.
      mkdir -p "$tmpdir/wrapped"
      mv "$extract_dir/$asset_bin" "$tmpdir/wrapped/$bin_name"
      extracted="$tmpdir/wrapped"
      ;;
    *)
      fail "_install_from_github_release: unknown layout: $layout"
      ;;
  esac

  _install_into_local "$lc_name" "$tag" "$bin_name" "$extracted"

  success "Installed $display_name $tag"
}

# Ensure <cmd> is on PATH; if missing, install <pkg> (defaults to <cmd>) via the
# platform package manager. <display> (defaults to <cmd>) names the tool in log
# messages. No-op in DRY mode after logging. Shared by ensure_jq, the inline
# minisign/Erlang calls in languages.sh, and the Linux branch of ensure_clang.
ensure_pkg() {
  local cmd="$1" pkg="${2:-$1}" display="${3:-$1}"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  info "$display not found; installing..."
  [[ "$DRY" == "true" ]] && return 0
  case "$(detect_platform)" in
    debian) sudo apt install -y "$pkg" || fail "Failed to install $pkg" ;;
    arch)   sudo pacman -S --needed --noconfirm "$pkg" || fail "Failed to install $pkg" ;;
    mac)    brew install "$pkg" || fail "Failed to install $pkg" ;;
    *)      fail "Cannot install $pkg on this platform" ;;
  esac
  success "Installed $display"
}

# Install jq if missing. Required to parse GitHub release metadata (and Zig index.json).
ensure_jq() { ensure_pkg jq; }

# xz-utils: required to extract the Zig .tar.xz in `dotfile languages zig`.
DEBIAN_PACKAGES=(
  curl git xz-utils zsh procps file
)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    _run_linux_home_manager_bootstrap "Failed to update apt" \
      sudo apt update -y
    _run_linux_home_manager_bootstrap "Failed to upgrade apt packages" \
      sudo apt upgrade -y
    _home_manager_switch
  fi
  success "Finished update for Debian"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    _run_linux_home_manager_bootstrap "Failed to install Debian packages" \
      sudo apt install -y "${DEBIAN_PACKAGES[@]}"
    _home_manager_switch
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl git zsh
)

function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    _run_linux_home_manager_bootstrap "Failed to update pacman" \
      sudo pacman -Syu --noconfirm
    _home_manager_switch
  fi
  success "Finished update for Arch Linux"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    _run_linux_home_manager_bootstrap "Failed to install Arch packages" \
      sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}"
    _home_manager_switch
  fi
  success "Finished install for Arch Linux"
}

function _load_nix_profile {
  local profile status
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    /nix/var/nix/profiles/default/etc/profile.d/nix.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    # shellcheck disable=SC1090
    if [[ -f "$profile" ]]; then
      status=0
      case $- in
        *u*)
          set +u
          source "$profile" || status=$?
          set -u
          ;;
        *)
          source "$profile" || status=$?
          ;;
      esac
      (( status == 0 )) || return "$status"
    fi
  done
}

function _install_lix {
  info "Installing Lix/Nix..."
  curl -sSf -L https://install.lix.systems/lix | sh -s -- install \
    || fail "Failed to install Lix/Nix"
}

function _ensure_nix {
  _load_nix_profile
  if ! command -v nix >/dev/null 2>&1; then
    _install_lix
    _load_nix_profile
  fi
}

function _run_linux_home_manager_bootstrap {
  local fail_message="$1"
  shift
  "$@" || fail "$fail_message"
}

_cleanup_home_manager_migration_conflicts() {
  local base="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
  local path
  for path in \
    "$base/zsh-autosuggestions" \
    "$base/fast-syntax-highlighting" \
    "$base/fzf-tab" \
    "$HOME/.tmux/plugins/tmux-yank" \
    "$HOME/.tmux/plugins/catppuccin/tmux"; do
    if [[ -e "$path" || -L "$path" ]]; then
      info "Removing old imperative plugin install: $path"
      rm -rf "$path" || fail "Failed to remove $path"
    fi
    if [[ -e "$path.before-home-manager" || -L "$path.before-home-manager" ]]; then
      info "Removing old Home Manager plugin backup: $path.before-home-manager"
      rm -rf "$path.before-home-manager" || fail "Failed to remove $path.before-home-manager"
    fi
  done

  local ghostty="$HOME/.config/ghostty"
  local target="$DOTFILES_DIR/config/unix/config/ghostty"
  if [[ -L "$ghostty" && "$(resolve_symlink "$ghostty")" == "$target" ]]; then
    info "Removing old repo-linked Ghostty config dir: $ghostty"
    rm -f "$ghostty" || fail "Failed to remove $ghostty"
  fi

  for path in \
    "$HOME/.local/bin/codex" \
    "$HOME/.local/bin/codebase-memory-mcp" \
    "$HOME/.bun/bin/codex" \
    "$HOME/.bun/install/global/node_modules/@openai/codex" \
    "$HOME/.bun/install/global/node_modules/@openai/codex-linux-arm64" \
    "$HOME/.bun/install/global/node_modules/@openai/codex-linux-x64"; do
    if [[ -e "$path" || -L "$path" ]]; then
      info "Removing old imperative agent tool install: $path"
      rm -rf "$path" || fail "Failed to remove $path"
    fi
  done
  for path in "$HOME"/.local/codex-*; do
    [[ -e "$path" || -L "$path" ]] || continue
    info "Removing old imperative agent tool install: $path"
    rm -rf "$path" || fail "Failed to remove $path"
  done
}

function _home_manager_switch {
  _ensure_nix
  local target
  target="$(_linux_home_manager_target)"
  if command -v home-manager >/dev/null 2>&1; then
    _run_nix_managed_switch "home-manager switch failed" \
      home-manager switch --flake "$target"
  else
    _run_nix_managed_switch "home-manager bootstrap switch failed" \
      nix run "$DOTFILES_DIR#home-manager" -- switch --flake "$target"
  fi
}

_host_config_value() {
  nix eval --raw --file "$DOTFILES_DIR/config/host.nix" "$1"
}

function _linux_home_manager_target {
  local username
  username="$(_host_config_value username)" \
    || fail "Failed to resolve Linux Home Manager username"
  echo "$DOTFILES_DIR#${username}@linux"
}

function _darwin_flake_target {
  echo "$DOTFILES_DIR#mac"
}

function _nixos_flake_target {
  echo "$DOTFILES_DIR#$(_host_config_value hostName)"
}

function _dry_run_nix_managed_switch {
  info "Would run: $*"
}

function _run_nix_managed_switch {
  local fail_message="$1"
  shift
  _cleanup_home_manager_migration_conflicts
  "$@" || fail "$fail_message"
}

function _darwin_rebuild_switch {
  _ensure_nix
  local target
  target="$(_darwin_flake_target)"
  if command -v darwin-rebuild >/dev/null 2>&1; then
    _run_nix_managed_switch "darwin-rebuild switch failed" \
      sudo HOME=/var/root darwin-rebuild switch --flake "$target"
  else
    _run_nix_managed_switch "nix-darwin bootstrap switch failed" \
      sudo HOME=/var/root nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake "$target"
  fi
}

function update_mac {
  info "Updating packages for Mac..."
  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo HOME=/var/root darwin-rebuild switch --flake "$(_darwin_flake_target)"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
  fi
  success "Finished update for Mac"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo HOME=/var/root darwin-rebuild switch --flake "$(_darwin_flake_target)"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
  fi
  success "Finished install for Mac"
}

function set_zsh_default {
  info "Changing default shell to zsh..."
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    nixos|mac)
      info "Shell is managed declaratively on $platform; skipping chsh"
      success "Finished changing zsh as default"
      return
      ;;
  esac
  if [[ "$DRY" == "false" ]]; then
    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [[ -z "$zsh_path" ]]; then
      info "zsh not installed; skipping default shell change"
    elif [[ "$SHELL" == "$zsh_path" || "$(basename "$SHELL")" == "zsh" ]]; then
      info "Already has zsh as default shell"
    else
      chsh -s "$zsh_path"
    fi
  fi
  success "Finished changing zsh as default"
}

function _nixos_rebuild_switch {
  local upgrade="${1:-false}"
  local target="$(_nixos_flake_target)"
  local args=(switch)
  local fail_message="nixos-rebuild switch failed"

  if [[ "$upgrade" == "true" ]]; then
    args+=(--upgrade)
    fail_message="nixos-rebuild switch --upgrade failed"
  fi

  [[ "$DRY" == "true" ]] && _dry_run_nix_managed_switch sudo nixos-rebuild "${args[@]}" --flake "$target"
  if [[ "$DRY" == "false" ]]; then
    _run_nix_managed_switch "$fail_message" sudo nixos-rebuild "${args[@]}" --flake "$target"
  fi
}

# Reprovision NixOS from this repo's flake. System packages come from the
# rebuild; agent extensions install after it.
# Usage: install_nixos
function install_nixos {
  info "Installing packages for NixOS..."
  _nixos_rebuild_switch
  success "Finished install for NixOS"
}

# Update NixOS by rebuilding this repo's flake with channel upgrade.
# Usage: update_nixos
function update_nixos {
  info "Updating packages for NixOS..."
  _nixos_rebuild_switch true
  success "Finished update for NixOS"
}

function update_packages {
  info "Updating packages..."
  case "$(detect_platform)" in
    nixos)   update_nixos ;;
    debian)  update_debian ;;
    arch)    update_arch ;;
    mac)     update_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  success "Finished update"
}

function install_packages {
  info "Installing packages..."
  case "$(detect_platform)" in
    nixos)   install_nixos ;;
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  set_zsh_default
  success "Finished install"
}
