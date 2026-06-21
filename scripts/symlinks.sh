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

  # SSH config lives in shared/.ssh/config but must land at ~/.ssh/config
  # (not ~/.config/.ssh), so link only the config file to preserve any
  # existing keys in ~/.ssh.
  local ssh_src="$DOTFILES_DIR/config/shared/.ssh/config"
  if [[ -f "$ssh_src" ]]; then
    if [[ "$DRY" != "true" ]]; then
      mkdir -p "$HOME/.ssh" || fail "Failed to create $HOME/.ssh"
    fi
    link_files "$ssh_src" "$HOME/.ssh/config"
  fi

  # AI tool configs live in their own dotfolders under $HOME (not ~/.config),
  # alongside runtime state we don't want to track. Link only the tracked
  # config files to leave caches, sessions, credentials, etc. untouched.
  local claude_src="$DOTFILES_DIR/config/shared/ai/claude/settings.json"
  if [[ -f "$claude_src" ]]; then
    if [[ "$DRY" != "true" ]]; then
      mkdir -p "$HOME/.claude" || fail "Failed to create $HOME/.claude"
    fi
    link_files "$claude_src" "$HOME/.claude/settings.json"
  fi

  # OpenCode keeps its user config under XDG ~/.config/opencode/ alongside
  # plugin runtime artifacts (node_modules, package.json, bun.lock). Upstream
  # explicitly excludes those from tracking via the dir's own .gitignore, so
  # we link only the hand-edited config file.
  local opencode_dir="$DOTFILES_DIR/config/shared/ai/opencode"
  if [[ -f "$opencode_dir/opencode.json" || -f "$opencode_dir/AGENTS.md" ]]; then
    if [[ "$DRY" != "true" ]]; then
      mkdir -p "$HOME/.config/opencode" || fail "Failed to create $HOME/.config/opencode"
    fi
  fi
  if [[ -f "$opencode_dir/opencode.json" ]]; then
    link_files "$opencode_dir/opencode.json" "$HOME/.config/opencode/opencode.json"
  fi
  if [[ -f "$opencode_dir/AGENTS.md" ]]; then
    link_files "$opencode_dir/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
  fi

  # Link the repo-root `dotfile` entry point into $HOME/.local/bin so users
  # can run `dotfile` from any shell.
  if [[ -f "$DOTFILES_DIR/dotfile" ]]; then
    mkdir -p "$HOME/.local/bin" || fail "Failed to create $HOME/.local/bin"
    link_files "$DOTFILES_DIR/dotfile" "$HOME/.local/bin/dotfile"
  fi
}
