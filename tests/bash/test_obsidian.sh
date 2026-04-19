#!/bin/bash
# Tests for scripts/obsidian.sh (Obsidian headless sync setup).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh obsidian.sh
  mock_uname Linux
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

# Helper: install a fake executable in FAKE_BIN that runs $body.
mock_cmd() {
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
}

# ---------------------------------------------------------------------------
# _obsidian_check_prereqs
# ---------------------------------------------------------------------------

test_check_prereqs_fails_on_non_linux() {
  mock_uname Darwin

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail on non-Linux" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "only supported on Linux"
}

test_check_prereqs_fails_when_npm_missing() {
  # Restrict PATH to exclude nvm-injected npm. /usr/bin:/bin is enough
  # for any other basic tools obsidian.sh might need; npm must not appear.
  export PATH="$FAKE_BIN:/usr/bin:/bin"

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail when npm missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "npm not found"
}

test_check_prereqs_fails_when_systemctl_missing() {
  mock_cmd npm 'exit 0'
  # Override the `command` builtin so that `command -v systemctl` returns
  # non-zero (simulating systemctl absent) regardless of what is on PATH.
  # systemctl may live in /bin (which is /usr/bin on Arch) so PATH tricks
  # alone cannot hide it.
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "systemctl" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail when systemctl missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "systemctl not found"
}

test_check_prereqs_succeeds_with_all_tools() {
  mock_cmd npm 'exit 0'
  mock_cmd systemctl 'exit 0'  # any --user show-environment call returns 0

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should succeed with all tools ($output)" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# _obsidian_install_cli
# ---------------------------------------------------------------------------

test_install_cli_dry_run_does_not_call_npm() {
  DRY=true
  # Canary: any npm invocation in DRY mode is a regression.
  mock_cmd npm 'echo "unexpected npm call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should not call npm in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run: npm install -g obsidian-headless"
}

test_install_cli_already_installed_short_circuits() {
  # `ob` present on PATH → command -v ob succeeds → npm should not be called.
  mock_cmd ob 'exit 0'
  mock_cmd npm 'echo "unexpected npm call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should short-circuit when ob present ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already installed"
}

test_install_cli_invokes_npm_when_missing() {
  # No `ob` mock → command -v ob fails → npm install runs.
  mock_cmd npm 'exit 0'

  local output exit_code=0
  output=$(_obsidian_install_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_cli should succeed when npm exits 0 ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing"
}

# ---------------------------------------------------------------------------
# _obsidian_login
# ---------------------------------------------------------------------------

test_login_skips_when_already_logged_in() {
  # `ob sync-list-remote` exits 0 → already logged in → `ob login` must NOT run.
  mock_cmd ob 'case "$1" in
    sync-list-remote) exit 0 ;;
    login) echo "unexpected ob login call" >&2; exit 99 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_login 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_login should succeed when already logged in ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Already logged in"
}

test_login_dry_run_does_not_call_ob() {
  DRY=true
  # Canary: any ob invocation in DRY mode is a regression.
  mock_cmd ob 'echo "unexpected ob call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_login 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_login should not call ob in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run: ob login"
}

# ---------------------------------------------------------------------------
# _obsidian_pick_vault
# ---------------------------------------------------------------------------

test_pick_vault_dry_run_returns_example() {
  DRY=true

  local stdout
  stdout=$(_obsidian_pick_vault 2>/dev/null)

  assert_equals "example-vault" "$stdout"
}

# ---------------------------------------------------------------------------
# _obsidian_setup_vault
# ---------------------------------------------------------------------------

test_setup_vault_dry_run_does_not_mkdir_or_call_ob() {
  DRY=true
  mock_cmd ob 'echo "unexpected ob call: $*" >&2; exit 99'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_setup_vault "test-vault" "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should not call ob in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  if [ -d "$vault_path" ]; then
    echo "  FAILED: _obsidian_setup_vault should not create vault dir in DRY mode" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run"
}

test_setup_vault_skips_when_already_configured() {
  local vault_path="$HOME/documents/obsidian/test-vault"
  mkdir -p "$vault_path"
  # sync-status exits 0 → already configured → sync-setup must NOT run.
  mock_cmd ob 'case "$1" in
    sync-status) exit 0 ;;
    sync-setup) echo "unexpected ob sync-setup call" >&2; exit 99 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_setup_vault "test-vault" "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should skip when configured ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already configured"
}

# ---------------------------------------------------------------------------
# _obsidian_install_service
# ---------------------------------------------------------------------------

test_install_service_dry_run_writes_nothing() {
  DRY=true
  # ob must be on PATH so command -v ob succeeds (the helper resolves the path).
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'echo "unexpected systemctl call: $*" >&2; exit 99'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should not call systemctl in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  if [ -f "$OBSIDIAN_SERVICE_PATH" ]; then
    echo "  FAILED: _obsidian_install_service should not write service file in DRY mode" >> "$ERROR_FILE"
  fi
}

test_install_service_writes_unit_and_enables() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should succeed ($output)" >> "$ERROR_FILE"
  fi
  assert_file_exists "$OBSIDIAN_SERVICE_PATH"

  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  assert_contains "$unit_content" "ob sync --path $vault_path --continuous"
  assert_contains "$unit_content" "WantedBy=default.target"
}

test_install_service_skips_when_file_exists_without_force() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'
  FORCE=false
  mkdir -p "$(dirname "$OBSIDIAN_SERVICE_PATH")"
  echo "SENTINEL_PRE_EXISTING_CONTENT" > "$OBSIDIAN_SERVICE_PATH"

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should succeed without overwriting ($output)" >> "$ERROR_FILE"
  fi
  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  assert_contains "$unit_content" "SENTINEL_PRE_EXISTING_CONTENT"
  assert_contains "$output" "use -f to overwrite"
}

test_install_service_force_overwrites() {
  mock_cmd ob 'exit 0'
  mock_cmd systemctl 'exit 0'
  FORCE=true
  mkdir -p "$(dirname "$OBSIDIAN_SERVICE_PATH")"
  echo "SENTINEL_PRE_EXISTING_CONTENT" > "$OBSIDIAN_SERVICE_PATH"

  local vault_path="$HOME/documents/obsidian/test-vault"
  local output exit_code=0
  output=$(_obsidian_install_service "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_install_service should overwrite with FORCE ($output)" >> "$ERROR_FILE"
  fi
  local unit_content
  unit_content=$(cat "$OBSIDIAN_SERVICE_PATH")
  if [[ "$unit_content" == *"SENTINEL_PRE_EXISTING_CONTENT"* ]]; then
    echo "  FAILED: _obsidian_install_service with FORCE should overwrite sentinel" >> "$ERROR_FILE"
  fi
  assert_contains "$unit_content" "ob sync --path $vault_path --continuous"
}
