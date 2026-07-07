#!/usr/bin/env bash
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
#!/usr/bin/env bash
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

test_check_prereqs_fails_when_ob_missing() {
  export PATH="$FAKE_BIN:/usr/bin:/bin"

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should fail when ob missing" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "ob not found"
  assert_contains "$output" "dotfile update"
}

test_check_prereqs_succeeds_with_all_tools() {
  mock_cmd ob 'exit 0'

  local output exit_code=0
  output=$(_obsidian_check_prereqs 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_check_prereqs should succeed with all tools ($output)" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# _obsidian_check_cli
# ---------------------------------------------------------------------------

test_check_cli_dry_run_only_checks_path() {
  DRY=true

  local output exit_code=0
  output=$(_obsidian_check_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_check_cli should only check PATH in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would verify ob is on PATH"
}

test_check_cli_reports_nix_managed_ob() {
  mock_cmd ob 'exit 0'

  local output exit_code=0
  output=$(_obsidian_check_cli 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_check_cli should report ob path ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "obsidian-headless found at"
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

test_setup_obsidian_skips_reconfiguring_existing_sync() {
  local vault_path="$HOME/documents/obsidian/test-vault"
  mkdir -p "$vault_path"
  mock_cmd ob 'case "$1" in
    sync-status) exit 0 ;;
    sync-list-remote|login|sync-setup)
      echo "unexpected ob $1 call" >&2
      exit 99
      ;;
    sync) exit 0 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(setup_obsidian 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: setup_obsidian should skip reconfiguring existing sync ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already configured"
  assert_contains "$output" "managed by Home Manager"
}

test_start_service_dry_run_does_not_call_systemctl() {
  DRY=true
  mock_cmd systemctl 'echo "unexpected systemctl call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(_obsidian_start_service 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_start_service should not call systemctl in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Would run: systemctl --user restart obsidian-sync.service"
}

test_start_service_skips_when_home_manager_unit_missing() {
  mock_cmd systemctl 'case "$*" in
    "--user show-environment") exit 0 ;;
    "--user cat obsidian-sync.service") exit 1 ;;
    "--user restart obsidian-sync.service")
      echo "unexpected restart" >&2
      exit 99
      ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_start_service 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: _obsidian_start_service should skip missing Home Manager unit ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "is not installed yet"
  assert_contains "$output" "dotfile update"
}
