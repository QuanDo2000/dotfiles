#!/bin/bash

: "${DOTFILES_DIR:=$HOME/dotfiles}"

function link_files {
  local src=$1 dst=$2
  # overwrite_all/backup_all/skip_all may be set by the caller (e.g.
  # setup_symlinks).  Default to "false" when called standalone.
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
      if [[ -L "$dst" ]] && [[ "$(readlink "$dst")" == "$src" ]]; then
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
      rm -rf "$dst" || fail "Failed to remove $dst"
      success "Removed $dst"
    fi

    if [[ "$backup" == "true" || "$backup_all" == "true" ]]; then
      mv "$dst" "${dst}.backup" || fail "Failed to backup $dst"
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

function copy_file {
  local src=$1 dst=$2
  info "Copying $src to $dst"
  if [[ "$DRY" == "true" ]]; then
    return
  fi

  if [[ -f "$dst" ]] && [[ "$FORCE" != "true" ]]; then
    if diff -q "$src" "$dst" >/dev/null 2>&1; then
      success "Skipped $src (already up to date)"
      return
    fi
    user "File already exists: $dst, overwrite? [y/N]"
    local action
    read -n 1 -r action
    if [[ "$action" != "y" && "$action" != "Y" ]]; then
      success "Skipped $src"
      return
    fi
  fi

  cp "$src" "$dst" || fail "Failed to copy $src to $dst"
  success "Copied $src to $dst"
}

function setup_symlinks_folder {
  local root=$1
  info "Setting up symlinks for $root..."

  if [[ ! -d "$root" ]]; then
    info "$root doesn't exist"
    return
  fi

  # Setup symlinks for direct files (copy .zshrc instead of linking)
  while IFS= read -r -d '' src <&3; do
    local name dst
    name="$(basename "$src")"
    dst="$HOME/$name"
    if [[ "$name" == ".zshrc" ]]; then
      copy_file "$src" "$dst"
    else
      link_files "$src" "$dst"
    fi
  done 3< <(find "$root" -maxdepth 1 -type f -print0)

  # Setup symlinks for bin files
  if [[ -d "$root/bin" ]]; then
    if [[ ! -d "$HOME/.local/bin" ]]; then
      info "$HOME/.local/bin doesn't exist. Creating folder..."
      mkdir -p "$HOME/.local/bin" || fail "Failed to create $HOME/.local/bin"
    fi
    while IFS= read -r -d '' src <&3; do
      local dst="$HOME/.local/bin/$(basename "$src")"
      link_files "$src" "$dst"
    done 3< <(find "$root/bin" -maxdepth 1 -type f -print0)
  fi

  # Setup symlinks for config folders
  if [[ ! -d "$root/config" ]]; then
    info "$root/config doesn't exist"
    return
  fi
  if [[ ! -d "$HOME/.config" ]]; then
    info "$HOME/.config doesn't exist. Creating folder..."
    mkdir -p "$HOME/.config" || fail "Failed to create $HOME/.config"
  fi
  while IFS= read -r -d '' src <&3; do
    local dst="$HOME/.config/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root/config" -mindepth 1 -maxdepth 1 -type d -print0)

  success "Finished setting up symlinks for $root"
}

function setup_symlinks {
  local overwrite_all=false backup_all=false skip_all=false

  if [[ "$FORCE" == "true" ]]; then
    overwrite_all=true
  fi

  setup_symlinks_folder "$DOTFILES_DIR/shared"
  setup_symlinks_folder "$DOTFILES_DIR/unix"
  if [[ "$(uname)" == "Darwin" ]]; then
    setup_symlinks_folder "$DOTFILES_DIR/mac"
  fi
}
