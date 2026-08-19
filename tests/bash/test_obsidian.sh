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

test_setup_obsidian_dry_run_does_not_require_ob_or_probe_vaults() {
  export DRY=true
  export PATH="$FAKE_BIN:/usr/bin:/bin"
  mkdir -p "$HOME/Documents/existing-vault"
  printf 'should not be probed\n' > "$HOME/Documents/existing-vault/sentinel"

  local output exit_code=0
  output=$(setup_obsidian 2>&1) || exit_code=$?

  assert_equals "0" "$exit_code"
  assert_contains "$output" "Would run: ob login (interactive)"
  assert_contains "$output" "Would run: ob sync-setup"
  assert_file_exists "$HOME/Documents/existing-vault/sentinel"
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

test_logged_in_vault_list_is_reused_for_selection() {
  export OBSIDIAN_TEST_CALLS="$TEST_TMPDIR/remote-list-calls"
  mock_cmd ob 'case "$1" in
    sync-list-remote)
      printf "call\n" >> "$OBSIDIAN_TEST_CALLS"
      printf "Team Notes\n"
      ;;
    login) echo "unexpected ob login call" >&2; exit 99 ;;
    *) exit 0 ;;
  esac'

  _obsidian_login >/dev/null
  local vault listing="$TEST_TMPDIR/vault-listing"
  vault=$(_obsidian_pick_vault <<< "Team Notes" 2> "$listing")

  assert_equals "Team Notes" "$vault"
  assert_equals "1" "$(wc -l < "$OBSIDIAN_TEST_CALLS" | tr -d ' ')"
  assert_contains "$(<"$listing")" "Team Notes"
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
# Vault path validation
# ---------------------------------------------------------------------------

test_vault_path_accepts_single_component_inside_base() {
  mkdir -p "$OBSIDIAN_VAULT_BASE"

  local actual exit_code=0
  actual=$(_obsidian_vault_path "Team Notes") || exit_code=$?

  assert_equals 0 "$exit_code"
  assert_equals "$(realpath -m -- "$OBSIDIAN_VAULT_BASE/Team Notes")" "$actual"
}

test_require_vault_path_accepts_symlinked_parent_spelling() {
  local real_root="$TEST_TMPDIR/real-home"
  local linked_root="$TEST_TMPDIR/linked-home"
  command mkdir -p "$real_root/Documents"
  ln -s "$real_root" "$linked_root"
  OBSIDIAN_VAULT_BASE="$linked_root/Documents"

  local output exit_code=0
  output=$(_obsidian_require_vault_path "test-vault" "$linked_root/Documents/test-vault" 2>&1) || exit_code=$?

  assert_equals 0 "$exit_code"
  assert_equals "" "$output"
}

test_setup_obsidian_rejects_traversal_vault_name() {
  export OBSIDIAN_TEST_CANARY="$TEST_TMPDIR/sync-setup-called"
  mock_cmd ob 'case "$1" in
    sync-list-remote) exit 0 ;;
    sync-status) exit 1 ;;
    sync-setup) touch "$OBSIDIAN_TEST_CANARY"; exit 0 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(printf '../outside\n' | setup_obsidian 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: setup_obsidian should reject a traversal vault name" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Invalid vault name"
  if [ -e "$HOME/outside" ] || [ -e "$OBSIDIAN_TEST_CANARY" ]; then
    echo "  FAILED: traversal vault name escaped Documents or reached ob sync-setup" >> "$ERROR_FILE"
  fi
}

test_existing_vault_scan_skips_symlink_escape() {
  local outside="$TEST_TMPDIR/outside-vault"
  local linked="$OBSIDIAN_VAULT_BASE/linked-vault"
  export OBSIDIAN_TEST_CANARY="$TEST_TMPDIR/sync-status-called"
  mkdir -p "$OBSIDIAN_VAULT_BASE" "$outside"
  ln -s "$outside" "$linked"
  mock_cmd ob 'case "$1" in
    sync-status) touch "$OBSIDIAN_TEST_CANARY"; exit 0 ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_existing_vault_path) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: existing vault scan should reject symlink escapes ($output)" >> "$ERROR_FILE"
  fi
  if [ -e "$OBSIDIAN_TEST_CANARY" ]; then
    echo "  FAILED: existing vault scan passed escaped path to ob" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# _obsidian_setup_vault
# ---------------------------------------------------------------------------

test_setup_vault_rechecks_path_after_directory_creation() {
  local vault_path="$OBSIDIAN_VAULT_BASE/race-vault"
  local outside="$TEST_TMPDIR/outside-vault"
  export OBSIDIAN_TEST_CANARY="$TEST_TMPDIR/ob-called"
  command mkdir -p "$OBSIDIAN_VAULT_BASE" "$outside"
  mock_cmd ob 'touch "$OBSIDIAN_TEST_CANARY"; exit 0'
  mkdir() {
    command mkdir "$@"
    if [[ " $* " == *" $vault_path "* ]]; then
      command rmdir "$vault_path"
      ln -s "$outside" "$vault_path"
    fi
  }

  local output exit_code=0
  output=$(_obsidian_setup_vault "race-vault" "$vault_path" 2>&1) || exit_code=$?
  unset -f mkdir

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should reject a post-mkdir symlink swap" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Invalid vault"
  if [ -e "$OBSIDIAN_TEST_CANARY" ]; then
    echo "  FAILED: post-mkdir symlink escape reached ob" >> "$ERROR_FILE"
  fi
}

test_setup_vault_rejects_path_outside_base() {
  local vault_path="$HOME/outside-vault"
  export OBSIDIAN_TEST_CANARY="$TEST_TMPDIR/sync-setup-called"
  mock_cmd ob 'touch "$OBSIDIAN_TEST_CANARY"; exit 0'

  local output exit_code=0
  output=$(_obsidian_setup_vault "test-vault" "$vault_path" 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: _obsidian_setup_vault should reject a path outside the vault base" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Invalid vault path"
  if [ -e "$vault_path" ] || [ -e "$OBSIDIAN_TEST_CANARY" ]; then
    echo "  FAILED: unsafe vault path reached mkdir or ob" >> "$ERROR_FILE"
  fi
}

test_setup_vault_dry_run_does_not_mkdir_or_call_ob() {
  DRY=true
  mock_cmd ob 'echo "unexpected ob call: $*" >&2; exit 99'

  local vault_path="$HOME/Documents/test-vault"
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
  local vault_path="$HOME/Documents/test-vault"
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
  local vault_path="$HOME/Documents/test-vault"
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

test_setup_obsidian_uses_documents_vault_base() {
  local vault_path="$HOME/Documents/Sync"
  mkdir -p "$vault_path"
  mock_cmd ob 'case "$1" in
    sync-status) exit 0 ;;
    sync-list-remote|login|sync-setup)
      echo "unexpected ob $1 call" >&2
      exit 99
      ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(setup_obsidian 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: setup_obsidian should skip reconfiguring existing sync ($output)" >> "$ERROR_FILE"
  fi
  if [[ "$OBSIDIAN_VAULT_BASE" != "$HOME/Documents" ]]; then
    echo "  FAILED: Obsidian setup should place the Sync vault directly under Documents" >> "$ERROR_FILE"
  fi
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

test_start_service_skips_active_service_for_existing_vault() {
  mock_cmd systemctl 'case "$*" in
    "--user show-environment"|"--user cat obsidian-sync.service"|"--user is-active --quiet obsidian-sync.service") exit 0 ;;
    "--user restart obsidian-sync.service")
      echo "unexpected restart" >&2
      exit 99
      ;;
    *) exit 0 ;;
  esac'

  local output exit_code=0
  output=$(_obsidian_start_service true 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: existing vault should keep active sync service ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "already active"
}
