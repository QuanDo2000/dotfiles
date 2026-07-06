#!/usr/bin/env bash
set -eo pipefail

function install_extras {
  info "Installing extras"
  info "Extras are managed by Nix; skipping imperative plugin installs"
  success "Finished installing extras"
}
