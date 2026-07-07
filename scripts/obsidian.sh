#!/usr/bin/env bash
set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/obsidian_paths.sh"

OBSIDIAN_SERVICE_NAME="obsidian-sync.service"
OBSIDIAN_VAULT_BASE="$HOME/documents/obsidian"
OBSIDIAN_CONFIG_SOURCE="${OBSIDIAN_CONFIG_SOURCE:-$DOTFILES_DIR/config/shared/obsidian}"

function _obsidian_check_prereqs {
  if ! is_linux; then
    fail "Obsidian sync setup is only supported on Linux"
  fi
  if ! command -v ob >/dev/null 2>&1; then
    fail "ob not found. Run 'dotfile update' to install the Nix-managed obsidian-headless package"
  fi
}

function _obsidian_check_cli {
  info "Checking obsidian-headless..."
  if [[ "$DRY" == "true" ]]; then
    info "Would verify ob is on PATH"
    return
  fi
  success "obsidian-headless found at $(command -v ob)"
}

function _obsidian_login {
  info "Logging in to Obsidian Sync..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: ob login (interactive)"
    return
  fi
  if ob sync-list-remote >/dev/null 2>&1; then
    info "Already logged in; skipping ob login"
    return
  fi
  user "Follow the prompts to log in (email, password, 2FA):"
  ob login || fail "ob login failed"
  success "Logged in to Obsidian Sync"
}

function _obsidian_pick_vault {
  # Prints the chosen vault name on stdout. All other output goes to stderr so
  # the caller can capture the name cleanly.
  if [[ "$DRY" == "true" ]]; then
    echo "example-vault"
    return
  fi
  user "Remote vaults available on your account:" >&2
  ob sync-list-remote >&2 || fail "Failed to list remote vaults"
  printf '\n' >&2
  local vault_name=""
  while [[ -z "$vault_name" ]]; do
    printf '  [ ?? ] Enter the vault name to sync: ' >&2
    read -r vault_name
  done
  echo "$vault_name"
}

function _obsidian_setup_vault {
  local vault_name="$1"
  local vault_path="$2"
  info "Setting up local vault at $vault_path..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: mkdir -p $vault_path"
    info "Would run: ob sync-setup --vault \"$vault_name\" --path $vault_path"
    return
  fi
  mkdir -p "$vault_path" || fail "Failed to create $vault_path"
  if ob sync-status --path "$vault_path" >/dev/null 2>&1; then
    info "Vault at $vault_path is already configured; skipping ob sync-setup"
  else
    user "Follow the prompts for sync setup (e2ee password if prompted):"
    ob sync-setup --vault "$vault_name" --path "$vault_path" \
      || fail "ob sync-setup failed"
  fi
  success "Vault ready at $vault_path"
}

function _obsidian_existing_vault_path {
  local vault_path
  for vault_path in "$OBSIDIAN_VAULT_BASE"/*; do
    [[ -d "$vault_path" ]] || continue
    if ob sync-status --path "$vault_path" >/dev/null 2>&1; then
      echo "$vault_path"
      return 0
    fi
  done
  return 1
}

function _obsidian_start_service {
  info "Starting Home Manager-managed $OBSIDIAN_SERVICE_NAME..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: systemctl --user restart $OBSIDIAN_SERVICE_NAME"
    return
  fi
  if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    if ! systemctl --user cat "$OBSIDIAN_SERVICE_NAME" >/dev/null 2>&1; then
      info "$OBSIDIAN_SERVICE_NAME is not installed yet; run 'dotfile update' to activate the Home Manager service"
      return
    fi
    systemctl --user restart "$OBSIDIAN_SERVICE_NAME" \
      || fail "Failed to restart $OBSIDIAN_SERVICE_NAME; run 'dotfile update' to activate the Home Manager service"
  else
    info "systemd user session unavailable; run 'dotfile update' after login to activate $OBSIDIAN_SERVICE_NAME"
  fi
}

function _obsidian_apply_config {
  local target="${1:-$OBSIDIAN_CONFIG_VAULT}"
  if [[ ! -d "$OBSIDIAN_CONFIG_SOURCE" ]]; then
    info "Skipping Obsidian config apply: $OBSIDIAN_CONFIG_SOURCE not found"
    return
  fi
  if [[ "$DRY" == "true" ]]; then
    info "Would copy tracked Obsidian config to $target"
    return
  fi

  mkdir -p "$target" || fail "Failed to create $target"
  cp -R "$OBSIDIAN_CONFIG_SOURCE/." "$target/" \
    || fail "Failed to copy tracked Obsidian config to $target"
  success "Obsidian config applied to $target"
}

function setup_obsidian_config {
  if [[ "$FORCE" == "true" ]]; then
    info "Applying tracked Obsidian config..."
    _obsidian_apply_config "$OBSIDIAN_CONFIG_VAULT"
  else
    info "Checking tracked Obsidian config..."
    DOTFILE_DOCTOR_SKIP_NIX_EVAL=true doctor
  fi
}

function setup_obsidian {
  info "Setting up Obsidian headless sync..."
  _obsidian_check_prereqs
  _obsidian_check_cli

  local existing_vault_path
  if [[ "$FORCE" != "true" ]] && existing_vault_path="$(_obsidian_existing_vault_path)"; then
    info "Vault at $existing_vault_path is already configured; skipping Obsidian Sync setup"
    _obsidian_start_service
    success "$OBSIDIAN_SERVICE_NAME is managed by Home Manager"
    return
  fi

  _obsidian_login

  local vault_name
  vault_name="$(_obsidian_pick_vault)"
  [[ -n "$vault_name" ]] || fail "No vault name provided"

  local vault_path="$OBSIDIAN_VAULT_BASE/$vault_name"
  _obsidian_setup_vault "$vault_name" "$vault_path"
  _obsidian_start_service

  success "Vault ready. $OBSIDIAN_SERVICE_NAME is managed by Home Manager"
}
