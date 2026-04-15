#!/bin/bash
set -eo pipefail

OBSIDIAN_SERVICE_NAME="obsidian-sync.service"
OBSIDIAN_SERVICE_PATH="$HOME/.config/systemd/user/$OBSIDIAN_SERVICE_NAME"
OBSIDIAN_VAULT_BASE="$HOME/documents/obsidian"

function _obsidian_check_prereqs {
  if ! is_linux; then
    fail "Obsidian sync setup is only supported on Linux (systemd required)"
  fi
  if ! command -v npm >/dev/null 2>&1; then
    fail "npm not found. Install Node.js (e.g. via nvm) before running 'dotfile obsidian'"
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    fail "systemctl not found. systemd is required for the obsidian-sync service"
  fi
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    fail "systemd user instance is not available. Ensure you are on a systemd-based distro with a user session"
  fi
}

function _obsidian_install_cli {
  info "Installing obsidian-headless..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: npm install -g obsidian-headless"
    return
  fi
  if command -v ob >/dev/null 2>&1; then
    info "obsidian-headless already installed ($(command -v ob))"
  else
    npm install -g obsidian-headless || fail "Failed to install obsidian-headless"
  fi
  success "Finished installing obsidian-headless"
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

function _obsidian_install_service {
  local vault_path="$1"
  local ob_bin
  ob_bin="$(command -v ob || true)"
  [[ -n "$ob_bin" ]] || fail "ob binary not found on PATH"

  info "Installing systemd user unit $OBSIDIAN_SERVICE_NAME..."
  if [[ -f "$OBSIDIAN_SERVICE_PATH" && "$FORCE" != "true" ]]; then
    info "Service file already exists at $OBSIDIAN_SERVICE_PATH (use -f to overwrite)"
  else
    if [[ "$DRY" == "true" ]]; then
      info "Would write $OBSIDIAN_SERVICE_PATH pointing at $vault_path"
    else
      mkdir -p "$(dirname "$OBSIDIAN_SERVICE_PATH")"
      cat >"$OBSIDIAN_SERVICE_PATH" <<EOF
[Unit]
Description=Obsidian Sync (headless, continuous)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$ob_bin sync --path $vault_path --continuous
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
    fi
  fi

  info "Enabling and starting $OBSIDIAN_SERVICE_NAME..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: systemctl --user daemon-reload"
    info "Would run: systemctl --user enable --now $OBSIDIAN_SERVICE_NAME"
  else
    systemctl --user daemon-reload || fail "systemctl daemon-reload failed"
    systemctl --user enable --now "$OBSIDIAN_SERVICE_NAME" \
      || fail "Failed to enable/start $OBSIDIAN_SERVICE_NAME"
  fi
  success "Service $OBSIDIAN_SERVICE_NAME is active"
}

function setup_obsidian {
  info "Setting up Obsidian headless sync..."
  _obsidian_check_prereqs
  _obsidian_install_cli
  _obsidian_login

  local vault_name
  vault_name="$(_obsidian_pick_vault)"
  [[ -n "$vault_name" ]] || fail "No vault name provided"

  local vault_path="$OBSIDIAN_VAULT_BASE/$vault_name"
  _obsidian_setup_vault "$vault_name" "$vault_path"
  _obsidian_install_service "$vault_path"

  success "Obsidian sync is running continuously. Check status with: systemctl --user status $OBSIDIAN_SERVICE_NAME"
}
