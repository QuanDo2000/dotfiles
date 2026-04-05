#!/bin/bash

function link_files {
  local src=$1 dst=$2
  local overwrite=false backup=false skip=false action=false
  info "Linking $src to $dst"
  if [[ "$DRY" == "true" ]]; then
    return
  fi

  if [ -f "$dst" ] || [ -d "$dst" ] || [ -L "$dst" ]; then
    if [[ "$overwrite_all" == "false" && "$backup_all" == "false" && "$skip_all" == "false" ]]; then
      local current_src
      current_src="$(readlink "$dst")"

      if [[ "$current_src" == "$src" ]]; then
        skip=true
      else
        user "File already exists: $dst ($(basename "$src")), what do you want to do?\n\
                    [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"
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
        *) ;;
        esac
      fi
    fi

    if [[ "$overwrite" == "true" || "$overwrite_all" == "true" ]]; then
      rm -rf "$dst"
      success "Removed $dst"
    fi

    if [[ "$backup" == "true" || "$backup_all" == "true" ]]; then
      mv "$dst" "${dst}.backup"
      success "Moved $dst to ${dst}.backup"
    fi

    if [[ "$skip" == "true" || "$skip_all" == "true" ]]; then
      success "Skipped $src"
    fi
  fi

  if [[ "$skip" != "true" && "$skip_all" != "true" ]]; then
    ln -s "$1" "$2"
    success "Linked $1 to $2"
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
    dst="$HOME/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root" -maxdepth 1 -type f -print0)

  # Setup symlinks for config folders
  if [[ ! -d "$root/config" ]]; then
    info "$root/config doesn't exist"
    return
  fi
  if [[ ! -d "$HOME/.config" ]]; then
    info "$HOME/.config doesn't exist. Creating folder..."
    mkdir -p "$HOME/.config"
  fi
  while IFS= read -r -d '' src <&3; do
    dst="$HOME/.config/$(basename "$src")"
    link_files "$src" "$dst"
  done 3< <(find "$root/config" -mindepth 1 -maxdepth 1 -type d -print0)

  success "Finished setting up symlinks for $root"
}

function setup_symlinks {
  local overwrite_all=false backup_all=false skip_all=false

  if [[ "$FORCE" == "true" ]]; then
    overwrite_all=true
  fi

  setup_symlinks_folder "$HOME/dotfiles/shared"
  setup_symlinks_folder "$HOME/dotfiles/unix"
  if [[ "$(uname)" == "Darwin" ]]; then
    setup_symlinks_folder "$HOME/dotfiles/mac"
  fi
}
