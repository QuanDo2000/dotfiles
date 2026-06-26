#!/bin/bash
set -eo pipefail

: "${DOTFILES_DIR:=$HOME/dotfiles}"

function link_files {
  local src=$1 dst=$2
  # Inherit overwrite_all/backup_all/skip_all from the caller so "*-all"
  # choices persist across invocations within a single run; default to false.
  : "${overwrite_all:=false}"
  : "${backup_all:=false}"
  : "${skip_all:=false}"
  local overwrite=false backup=false skip=false
  local action
  info "Linking $src to $dst"
  if [[ "$DRY" == "true" ]]; then
    return
  fi

  if [[ -f "$dst" || -d "$dst" || -L "$dst" ]]; then
    if [[ "$overwrite_all" == "false" && "$backup_all" == "false" && "$skip_all" == "false" ]]; then
      if [[ -L "$dst" ]] && [[ "$(resolve_symlink "$dst")" == "$src" ]]; then
        skip=true
      elif [[ "$QUIET" == "true" ]]; then
        skip=true
      else
        user "File already exists: $dst ($(basename "$src")), what do you want to do?\n[s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
        read -n 1 -r action

        case "$action" in
        o)
          overwrite=true
          ;;
        O)
          overwrite_all=true
          ;;
        b)
          backup=true
          ;;
        B)
          backup_all=true
          ;;
        s)
          skip=true
          ;;
        S)
          skip_all=true
          ;;
        *)
          skip=true
          ;;
        esac
      fi
    fi

    if [[ "$overwrite" == "true" || "$overwrite_all" == "true" ]]; then
      rm -rf "$dst" 2>/dev/null \
        || fail "Failed to remove $dst (check permissions or whether it's in use)"
      success "Removed $dst"
    fi

    if [[ "$backup" == "true" || "$backup_all" == "true" ]]; then
      mv "$dst" "${dst}.backup" \
        || fail "Failed to backup $dst to ${dst}.backup (does ${dst}.backup already exist?)"
      success "Moved $dst to ${dst}.backup"
    fi

    if [[ "$skip" == "true" || "$skip_all" == "true" ]]; then
      success "Skipped $src"
    fi
  fi

  if [[ "$skip" != "true" && "$skip_all" != "true" ]]; then
    ln -s "$src" "$dst" || fail "Failed to link $src to $dst"
    success "Linked $src to $dst"
  fi
}

# Link a single tracked file into place, creating its parent dir, but only if
# the source exists. Used for carveouts where we link individual files rather
# than whole dirs (SSH, AI tool configs).
function _link_optional {
  local src=$1 dst=$2
  [[ -f "$src" ]] || return 0
  if [[ "$DRY" != "true" ]]; then
    mkdir -p "$(dirname "$dst")" || fail "Failed to create $(dirname "$dst")"
  fi
  link_files "$src" "$dst"
}

function setup_symlinks_folder {
  local root=$1
  info "Setting up symlinks for $root..."

  if [[ ! -d "$root" ]]; then
    info "$root doesn't exist"
    return
  fi

  # Setup symlinks for direct files
  while IFS= read -r -d '' src <&3; do
    local dst
    dst="$HOME/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root" -maxdepth 1 -type f -print0)

  # Setup symlinks for bin files
  if [[ -d "$root/bin" ]]; then
    mkdir -p "$HOME/.local/bin" || fail "Failed to create $HOME/.local/bin"
    while IFS= read -r -d '' src <&3; do
      local dst
      dst="$HOME/.local/bin/$(basename "$src")"
      link_files "$src" "$dst"
    done 3< <(find "$root/bin" -maxdepth 1 -type f -print0)
  fi

  # Setup symlinks for config files and folders. Both loose files (e.g.
  # starship.toml) and directories (e.g. nvim/) under config/ are linked
  # straight into ~/.config/, preserving their basename.
  if [[ ! -d "$root/config" ]]; then
    info "$root/config doesn't exist"
    return
  fi
  mkdir -p "$HOME/.config" || fail "Failed to create $HOME/.config"
  while IFS= read -r -d '' src <&3; do
    local dst
    dst="$HOME/.config/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root/config" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0)

  success "Finished setting up symlinks for $root"
}

# ~/.zshrc is machine-local (NOT tracked): it sources the tracked ~/.zshrc.base
# and is where tool installers (nvm, bun, pnpm, ...) append their lines, so those
# per-machine edits never touch the repo. Create the stub if missing; if an older
# setup left ~/.zshrc symlinked into the repo, replace it with a real stub.
function _ensure_local_zshrc {
  local dst="$HOME/.zshrc"
  if [[ -L "$dst" && "$(resolve_symlink "$dst")" == "$DOTFILES_DIR"/* ]]; then
    info "Replacing repo-linked $dst with a machine-local stub"
    [[ "$DRY" == "true" ]] || rm -f "$dst"
  fi
  [[ -e "$dst" ]] && return 0
  info "Creating machine-local $dst"
  if [[ "$DRY" != "true" ]]; then
    cat > "$dst" <<'EOF'
# Machine-local zsh config (NOT tracked in dotfiles).
# Sources the tracked base; tool installers append their lines below.
[ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"
EOF
    success "Created $dst"
  fi
}

function setup_symlinks {
  local overwrite_all=false backup_all=false skip_all=false

  if [[ "$FORCE" == "true" ]]; then
    overwrite_all=true
  fi

  setup_symlinks_folder "$DOTFILES_DIR/config/shared"
  setup_symlinks_folder "$DOTFILES_DIR/config/unix"
  if is_mac; then
    setup_symlinks_folder "$DOTFILES_DIR/config/mac"
  fi

  _ensure_local_zshrc

  # These configs live in dotfolders alongside runtime state we don't want to
  # track (caches, sessions, credentials, ~/.ssh keys, OpenCode node_modules),
  # so we link only the individual tracked files rather than whole dirs.
  # _link_optional creates each file's parent dir and skips when the source is
  # absent.
  local ai="$DOTFILES_DIR/config/shared/ai"
  _link_optional "$DOTFILES_DIR/config/shared/.ssh/config" "$HOME/.ssh/config"
  _link_optional "$ai/claude/settings.json" "$HOME/.claude/settings.json"
  _link_optional "$ai/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
  _link_optional "$ai/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"

  # Link the repo-root `dotfile` entry point into $HOME/.local/bin so users
  # can run `dotfile` from any shell.
  if [[ -f "$DOTFILES_DIR/dotfile" ]]; then
    mkdir -p "$HOME/.local/bin" || fail "Failed to create $HOME/.local/bin"
    link_files "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  fi
}
