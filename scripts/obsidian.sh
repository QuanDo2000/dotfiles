#!/usr/bin/env bash
set -eo pipefail

OBSIDIAN_SERVICE_NAME="obsidian-sync.service"
OBSIDIAN_VAULT_BASE="$HOME/Documents"

function _obsidian_check_prereqs {
  if ! is_linux; then
    fail "Obsidian sync setup is only supported on Linux"
  fi
  if [[ "$DRY" != "true" ]] && ! command -v ob >/dev/null 2>&1; then
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

function _obsidian_canonical_path {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
  else
    local parent
    parent="$(_obsidian_canonical_path "$(dirname "$path")")" || return 1
    printf '%s/%s\n' "$parent" "$(basename "$path")"
  fi
}

function _obsidian_vault_path {
  local vault_name="$1"
  [[ -n "$vault_name" && "$vault_name" != "." && "$vault_name" != ".." && "$vault_name" != */* ]] || return 1

  local base_path vault_path
  base_path="$(_obsidian_canonical_path "$OBSIDIAN_VAULT_BASE")" || return 1
  vault_path="$(_obsidian_canonical_path "$base_path/$vault_name")" || return 1
  [[ "$vault_path" == "$base_path"/* ]] || return 1
  printf '%s\n' "$vault_path"
}

function _obsidian_require_vault_path {
  local vault_name="$1"
  local vault_path="$2"
  local expected_path actual_path
  expected_path="$(_obsidian_vault_path "$vault_name")" || fail "Invalid vault name: $vault_name"
  actual_path="$(_obsidian_canonical_path "$vault_path")" || fail "Invalid vault path: $vault_path"
  [[ "$actual_path" == "$expected_path" ]] || fail "Invalid vault path: $vault_path"
}

function _obsidian_setup_vault {
  local vault_name="$1"
  local vault_path="$2"
  _obsidian_require_vault_path "$vault_name" "$vault_path"
  info "Setting up local vault at $vault_path..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: mkdir -p $vault_path"
    info "Would run: ob sync-setup --vault \"$vault_name\" --path $vault_path"
    return
  fi
  mkdir -p "$vault_path" || fail "Failed to create $vault_path"
  _obsidian_require_vault_path "$vault_name" "$vault_path"
  if ob sync-status --path "$vault_path" >/dev/null 2>&1; then
    info "Vault at $vault_path is already configured; skipping ob sync-setup"
  else
    user "Follow the prompts for sync setup (e2ee password if prompted):"
    _obsidian_require_vault_path "$vault_name" "$vault_path"
    ob sync-setup --vault "$vault_name" --path "$vault_path" \
      || fail "ob sync-setup failed"
  fi
  success "Vault ready at $vault_path"
}

function _obsidian_existing_vault_path {
  local candidate vault_path
  for candidate in "$OBSIDIAN_VAULT_BASE"/*; do
    [[ -d "$candidate" ]] || continue
    vault_path="$(_obsidian_vault_path "${candidate##*/}")" || continue
    _obsidian_require_vault_path "${candidate##*/}" "$vault_path"
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

function setup_obsidian {
  info "Setting up Obsidian headless sync..."
  _obsidian_check_prereqs
  _obsidian_check_cli

  local existing_vault_path
  if [[ "$DRY" != "true" && "$FORCE" != "true" ]] && existing_vault_path="$(_obsidian_existing_vault_path)"; then
    info "Vault at $existing_vault_path is already configured; skipping Obsidian Sync setup"
    _obsidian_start_service
    success "$OBSIDIAN_SERVICE_NAME is managed by Home Manager"
    return
  fi

  _obsidian_login

  local vault_name
  vault_name="$(_obsidian_pick_vault)"
  [[ -n "$vault_name" ]] || fail "No vault name provided"

  local vault_path
  vault_path="$(_obsidian_vault_path "$vault_name")" || fail "Invalid vault name: $vault_name"
  _obsidian_setup_vault "$vault_name" "$vault_path"
  _obsidian_start_service

  success "Vault ready. $OBSIDIAN_SERVICE_NAME is managed by Home Manager"
}
