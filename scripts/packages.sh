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
# Shared by setup_neovim/setup_lazygit/setup_jj here and by the language
# installers in languages.sh (install_zig/odin/gleam). Defined in packages.sh
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

function install_font_debian {
  # https://medium.com/source-words/how-to-manually-install-update-and-uninstall-fonts-on-linux-a8d09a3853b0
  info "Installing Fira Code..."
  if [[ "$DRY" == "false" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    if [ ! -f "$HOME/.local/share/fonts/FiraCodeNerdFont-Regular.ttf" ]; then
      cd "$HOME/.local/share/fonts" || fail "Failed to enter fonts directory"
      curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf \
        || fail "Failed to download Fira Code font"
      command -v fc-cache >/dev/null 2>&1 && fc-cache -f -v
      cd "$HOME" || fail "Failed to return to home directory"
    else
      info "Already installed font Fira Code"
    fi
  fi
  success "Finished installing Fira Code"
}

function setup_fdfind {
  info "Ensuring 'fd' is available in '.local/bin'..."
  if [[ "$DRY" == "false" ]]; then
    mkdir -p "$HOME/.local/bin"
    # 'fd' is already callable as-is; we only normalize Debian's 'fdfind' name.
    if command -v fd >/dev/null 2>&1; then
      info "'fd' already available on PATH"
    elif command -v fdfind >/dev/null 2>&1; then
      if [ ! -L "$HOME/.local/bin/fd" ]; then
        ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
      else
        info "Already symlinked fdfind to '.local/bin/fd'"
      fi
    else
      info "fd not found on system; skipping symlink. Install 'fd' (ripgrep/ fd) manually or via your package manager"
    fi
  fi
  success "Finished ensuring fd in '.local/bin'"
}

# Bootstrap yay (AUR helper) on Arch. Clones yay-bin from the AUR and builds
# it with makepkg. Idempotent: no-op if yay is already on PATH.
# Usage: setup_yay
function setup_yay {
  info "Installing yay..."
  if [[ "$DRY" == "false" ]]; then
    if command -v yay >/dev/null 2>&1; then
      info "Already installed yay"
      success "Finished yay"
      return
    fi
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      fail "setup_yay must not run as root (makepkg refuses root)"
    fi
    command -v git >/dev/null 2>&1 || fail "git required for setup_yay"
    command -v makepkg >/dev/null 2>&1 || fail "makepkg required for setup_yay (install base-devel)"

    local build_dir
    build_dir="$(mktemp -d -t yay-bin.XXXXXX)" || fail "Failed to create temp dir"
    # EXIT covers fail()'s exit 1 path; RETURN covers normal returns. Without
    # EXIT, every fail() in this function would leak $build_dir under /tmp.
    # shellcheck disable=SC2064
    trap "rm -rf '$build_dir'" EXIT RETURN
    git clone https://aur.archlinux.org/yay-bin.git "$build_dir" \
      || fail "Failed to clone yay-bin AUR repo"
    (cd "$build_dir" && makepkg -si --noconfirm) \
      || fail "Failed to build/install yay-bin"
  fi
  success "Finished yay"
}

# Map `uname -m` to the arch slug used by lazygit release assets.
_lazygit_arch() {
  case "$(uname -m)" in
    x86_64)        echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) fail "Unsupported arch for lazygit: $(uname -m)" ;;
  esac
}

# Install or update a flat-binary tool from its GitHub releases into ~/.local/bin.
# Debian only — Arch/macOS use their package managers. Idempotent: in install
# mode, no-op if <cmd> is already on PATH; --update always fetches the latest.
# <asset_fn> echoes the release asset filename given the tag (it varies per tool).
# Usage: setup_gh_binary <cmd> <owner/repo> <asset_fn> [--update]
function setup_gh_binary {
  local cmd="$1" repo="$2" asset_fn="$3"
  local update=false
  [[ "${4:-}" == "--update" ]] && update=true
  info "$(_action_verb "$update") $cmd..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v "$cmd" >/dev/null 2>&1; then
      info "Already installed $cmd"
      success "Finished $cmd"
      return
    fi
    ensure_jq
    local release_json tag
    release_json="$(http_get_retry "https://api.github.com/repos/$repo/releases/latest")" \
      || fail "Failed to fetch $cmd releases/latest"
    tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
    [[ -n "$tag" ]] || fail "Could not read tag_name from $cmd releases/latest"
    local asset
    asset="$("$asset_fn" "$tag")"
    _install_from_github_release "$cmd" "$cmd" "$release_json" "$tag" "$asset" "flat-binary" "$cmd"
  fi
  success "Finished $cmd"
}

# lazygit asset drops the leading 'v' from the tag (e.g. lazygit_0.44.2_Linux_x86_64.tar.gz).
_lazygit_asset() { echo "lazygit_${1#v}_Linux_$(_lazygit_arch).tar.gz"; }
# Install or update lazygit (Debian only — Arch uses pacman, macOS brew).
function setup_lazygit { setup_gh_binary lazygit jesseduffield/lazygit _lazygit_asset "${1:-}"; }

# Echo starship's Linux release asset arch for the current machine.
_starship_arch() {
  case "$(uname -m)" in
    x86_64)        echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) fail "Unsupported arch for starship: $(uname -m)" ;;
  esac
}

_starship_asset() { echo "starship-$(_starship_arch)-unknown-linux-gnu.tar.gz"; }

# Install or update the starship prompt. Arch installs it via pacman and macOS
# via brew (see ARCH_PACKAGES / MAC_BREW_PACKAGES); Debian apt does not reliably
# ship starship, so install the checked GitHub release into ~/.local/bin.
# Idempotent: in install mode, no-op if `starship` is already on PATH; --update
# always reinstalls the latest. Usage: setup_starship [--update]
function setup_starship {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "$(_action_verb "$update") starship..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v starship >/dev/null 2>&1; then
      info "Already installed starship"
      success "Finished starship"
      return
    fi
    ensure_jq
    local release_json tag asset
    release_json="$(http_get_retry "https://api.github.com/repos/starship/starship/releases/latest")" \
      || fail "Failed to fetch starship releases/latest"
    tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
    [[ -n "$tag" ]] || fail "Could not read tag_name from starship releases/latest"
    asset="$(_starship_asset)"
    _install_from_github_release starship starship "$release_json" "$tag" \
      "$asset" "flat-binary" "starship"
  fi
  success "Finished starship"
}

# Map `uname -m` to the arch slug used by jj (jujutsu) release assets.
_jj_arch() {
  case "$(uname -m)" in
    x86_64)        echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) fail "Unsupported arch for jj: $(uname -m)" ;;
  esac
}

# jj asset keeps the leading 'v' (e.g. jj-v0.42.0-x86_64-unknown-linux-musl.tar.gz).
_jj_asset() { echo "jj-${1}-$(_jj_arch)-unknown-linux-musl.tar.gz"; }
# Install or update jj/jujutsu (Debian only — Arch uses pacman, macOS brew).
function setup_jj { setup_gh_binary jj jj-vcs/jj _jj_asset "${1:-}"; }

# Echo codex's release triple (<arch>-<os>) for the current machine.
_codex_triple() {
  local arch os
  case "$(uname -m)" in
    x86_64)        arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) fail "Unsupported arch for codex: $(uname -m)" ;;
  esac
  if is_mac; then os=apple-darwin; else os=unknown-linux-musl; fi
  echo "${arch}-${os}"
}

# Install or update the OpenAI Codex CLI from GitHub releases into ~/.local/bin.
# Cross-platform (Linux + macOS): codex is not in apt/pacman/brew, so the static
# release binary is fetched with sha256 verification. The tarball ships the
# binary as codex-<triple>; it's renamed to `codex` on install. Idempotent:
# install mode no-ops if `codex` is on PATH; --update always fetches the latest.
# Usage: setup_codex [--update]
function setup_codex {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "$(_action_verb "$update") codex..."
  if [[ "$DRY" == "false" ]]; then
    if [[ "$update" == "false" ]] && command -v codex >/dev/null 2>&1; then
      info "Already installed codex"
      success "Finished codex"
      return
    fi
    if [[ "$update" == "true" ]] && command -v bun >/dev/null 2>&1; then
      bun add -g @openai/codex@latest || fail "Failed to update codex with bun"
      success "Finished codex"
      return
    fi
    ensure_jq
    local triple asset release_json tag
    triple="$(_codex_triple)"
    asset="codex-${triple}.tar.gz"
    release_json="$(http_get_retry "https://api.github.com/repos/openai/codex/releases/latest")" \
      || fail "Failed to fetch codex releases/latest"
    tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
    [[ -n "$tag" ]] || fail "Could not read tag_name from codex releases/latest"
    _install_from_github_release codex codex "$release_json" "$tag" \
      "$asset" "flat-binary" "codex" "codex-${triple}"
  fi
  success "Finished codex"
}

# Install or update codebase-memory-mcp. Usage: setup_codebase_memory_mcp [--update]
function setup_codebase_memory_mcp {
  local update=false
  [[ "${1:-}" == "--update" ]] && update=true
  info "$(_action_verb "$update") codebase-memory-mcp..."
  if [[ "$DRY" == "false" ]]; then
    if command -v codebase-memory-mcp >/dev/null 2>&1; then
      if [[ "$update" == "true" ]]; then
        codebase-memory-mcp update || fail "Failed to update codebase-memory-mcp"
      else
        info "Already installed codebase-memory-mcp"
      fi
    else
      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash \
        || fail "Failed to install codebase-memory-mcp"
    fi
  fi
  success "Finished codebase-memory-mcp"
}

# build-essential: nvim-treesitter compiles parsers with cc.
# xz-utils: required to extract the Zig .tar.xz in `dotfile languages zig`.
DEBIAN_PACKAGES=(
  build-essential curl git xz-utils nodejs
  unzip zsh tmux neovim fontconfig fzf fd-find ripgrep
  procps file zoxide
)

function update_debian {
  info "Updating packages for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt update -y || fail "Failed to update apt"
    sudo apt upgrade -y || fail "Failed to upgrade apt packages"

    setup_lazygit --update
    setup_jj --update
    setup_starship --update
    setup_codex --update
    setup_codebase_memory_mcp --update
  fi
  success "Finished update for Debian"
}

function install_debian {
  info "Installing packages and programs for Debian..."
  if [[ "$DRY" == "false" ]]; then
    sudo apt install -y "${DEBIAN_PACKAGES[@]}" \
      || fail "Failed to install Debian packages"

    install_font_debian
    setup_fdfind
    setup_lazygit
    setup_jj
    setup_starship
    setup_codex
    setup_codebase_memory_mcp
  fi
  success "Finished install for Debian"
}

ARCH_PACKAGES=(
  base-devel curl git zsh
)

function update_arch {
  info "Updating packages for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -Syu --noconfirm || fail "Failed to update pacman"

    _home_manager_switch
    setup_codex --update
    setup_codebase_memory_mcp --update
  fi
  success "Finished update for Arch Linux"
}

function install_arch {
  info "Installing packages and programs for Arch Linux..."
  if [[ "$DRY" == "false" ]]; then
    sudo pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}" \
      || fail "Failed to install Arch packages"

    _home_manager_switch
    setup_codex
    setup_codebase_memory_mcp
  fi
  success "Finished install for Arch Linux"
}

MAC_BREW_PACKAGES=(
  bash tmux git neovim fzf fd ripgrep font-fira-code-nerd-font
  gnupg pinentry-mac jesseduffield/lazygit/lazygit ast-grep zoxide jj starship node
)
MAC_BREW_CASKS=(ghostty)

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

_cleanup_home_manager_plugin_migration() {
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
}

_cleanup_home_manager_dotfile_migration() {
  local ghostty="$HOME/.config/ghostty"
  local target="$DOTFILES_DIR/config/unix/config/ghostty"
  if [[ -L "$ghostty" && "$(resolve_symlink "$ghostty")" == "$target" ]]; then
    info "Removing old repo-linked Ghostty config dir: $ghostty"
    rm -f "$ghostty" || fail "Failed to remove $ghostty"
  fi
}

function _home_manager_switch {
  _ensure_nix
  _cleanup_home_manager_plugin_migration
  _cleanup_home_manager_dotfile_migration
  if command -v home-manager >/dev/null 2>&1; then
    home-manager switch --flake "$DOTFILES_DIR#quando@arch" \
      || fail "home-manager switch failed"
  else
    nix run "$DOTFILES_DIR#home-manager" -- switch --flake "$DOTFILES_DIR#quando@arch" \
      || fail "home-manager bootstrap switch failed"
  fi
}

function _darwin_rebuild_switch {
  _ensure_nix
  _cleanup_home_manager_plugin_migration
  if command -v darwin-rebuild >/dev/null 2>&1; then
    sudo HOME=/var/root darwin-rebuild switch --flake "$DOTFILES_DIR#mac" \
      || fail "darwin-rebuild switch failed"
  else
    sudo HOME=/var/root nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake "$DOTFILES_DIR#mac" \
      || fail "nix-darwin bootstrap switch failed"
  fi
}

function update_mac {
  info "Updating packages for Mac..."
  [[ "$DRY" == "true" ]] && info "Would run: sudo HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
    setup_codex --update
    setup_codebase_memory_mcp --update
  fi
  success "Finished update for Mac"
}

function install_mac {
  info "Installing packages and programs for Mac..."
  [[ "$DRY" == "true" ]] && info "Would run: sudo HOME=/var/root darwin-rebuild switch --flake $DOTFILES_DIR#mac"
  if [[ "$DRY" == "false" ]]; then
    _darwin_rebuild_switch
    setup_codex
    setup_codebase_memory_mcp
  fi
  success "Finished install for Mac"
}

function set_zsh_default {
  info "Changing default shell to zsh..."
  if [[ "$(detect_platform)" == "nixos" ]]; then
    info "Shell is managed declaratively on NixOS; skipping chsh"
    success "Finished changing zsh as default"
    return
  fi
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

# Reprovision NixOS from this repo's flake. System packages come from the
# rebuild; agent extensions install after it.
# Usage: install_nixos
function install_nixos {
  info "Installing packages for NixOS..."
  [[ "$DRY" == "true" ]] && info "Would run: sudo nixos-rebuild switch --flake $DOTFILES_DIR#nixos"
  if [[ "$DRY" == "false" ]]; then
    _cleanup_home_manager_plugin_migration
    sudo nixos-rebuild switch --flake "$DOTFILES_DIR#nixos" \
      || fail "nixos-rebuild switch failed"
    setup_codebase_memory_mcp
  fi
  success "Finished install for NixOS"
}

# Update NixOS by rebuilding this repo's flake with channel upgrade.
# Usage: update_nixos
function update_nixos {
  info "Updating packages for NixOS..."
  [[ "$DRY" == "true" ]] && info "Would run: sudo nixos-rebuild switch --upgrade --flake $DOTFILES_DIR#nixos"
  if [[ "$DRY" == "false" ]]; then
    _cleanup_home_manager_plugin_migration
    sudo nixos-rebuild switch --upgrade --flake "$DOTFILES_DIR#nixos" \
      || fail "nixos-rebuild switch --upgrade failed"
    setup_codebase_memory_mcp --update
  fi
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
