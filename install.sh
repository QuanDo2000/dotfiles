#!/bin/bash
set -eo pipefail

# Global variables
DRY=false
DOTFILES_DIR="$HOME/dotfiles"
REPO_URL="https://github.com/QuanDo2000/dotfiles.git"

# Ensure the repo is cloned so we can source modules
function ensure_repo {
  if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Cloning dotfiles repo..."
    git clone "$REPO_URL" "$DOTFILES_DIR" || {
      echo "Failed to clone dotfiles repo"
      exit 1
    }
  fi
}

ensure_repo

# Source modules
SCRIPTS_DIR="$DOTFILES_DIR/scripts"
source "$SCRIPTS_DIR/utils.sh"
source "$SCRIPTS_DIR/packages.sh"
source "$SCRIPTS_DIR/extras.sh"
source "$SCRIPTS_DIR/symlinks.sh"
source "$SCRIPTS_DIR/verify.sh"

function update_repo {
  info "Updating dotfiles repo..."
  if [[ "$DRY" == "false" ]]; then
    cd "$DOTFILES_DIR" || return
    git pull || fail "Failed to pull dotfiles repo"
  fi
  success "Finished updating repo"
}

function setup_dotfiles {
  info "Setting up dotfiles..."
  install_packages
  update_repo
  install_extras
  setup_symlinks
  success "Done!"
}

function usage {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  packages    Install system packages only
  extras      Install oh-my-zsh, zsh plugins, tmux plugins
  zsh         Install oh-my-zsh and zsh plugins
  tmux        Install tmux plugins
  symlinks    Create symlinks only
  verify      Verify installation

Options:
  -d, --dry   Dry run (no changes made)
  -h, --help  Show this help message
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
  -d | --dry)
    DRY=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    break
    ;;
  esac
done

# Run command
case "${1:-all}" in
all) setup_dotfiles ;;
packages) install_packages ;;
extras) install_extras ;;
zsh)
  install_oh_my_zsh
  install_zsh_plugins
  ;;
tmux) install_tmux_plugins ;;
symlinks) setup_symlinks ;;
verify) verify ;;
*)
  fail "Unknown command: $1"
  usage
  exit 1
  ;;
esac
