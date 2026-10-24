#!/usr/bin/env bash
# Package-update integration tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

_init_update_test_repo() {
  mkdir -p "$DOTFILES_DIR"
  git init -q "$DOTFILES_DIR"
  git -C "$DOTFILES_DIR" config user.email test@example.com
  git -C "$DOTFILES_DIR" config user.name Test
  : > "$DOTFILES_DIR/.test-root"
  git -C "$DOTFILES_DIR" add .test-root
  git -C "$DOTFILES_DIR" commit -qm initial
}

test_updates_reject_linked_worktrees_before_locking() {
  _init_update_test_repo
  local repo="$DOTFILES_DIR" linked="$TEST_TMPDIR/linked" output status command
  git -C "$repo" worktree add -qb fixture "$linked"
  DOTFILES_DIR="$linked"
  DRY=false
  detect_platform() { printf 'debian\n'; }
  for command in update_packages update_ai; do
    status=0
    output="$("$command" 2>&1)" || status=$?
    assert_equals 1 "$status"
    assert_contains "$output" 'Linked worktrees are unsupported'
    assert_contains "$output" 'standalone checkout'
    assert_not_contains "$output" 'Another dependency update is already running'
    [[ ! -e "$repo/.git/dotfile-dependency-update.flock" ]] \
      || echo '  linked preflight acquired a lock' >> "$ERROR_FILE"
    assert_equals '' "$(git -C "$repo" status --porcelain)"
  done
}

test_updates_preserve_actual_lock_contention_diagnostic() {
  _init_update_test_repo
  DRY=false
  detect_platform() { printf 'debian\n'; }
  _acquire_dependency_update_lock
  local output status command
  for command in update_packages update_ai; do
    status=0
    output="$(DEPENDENCY_UPDATE_LOCK=; exec 8>&-; "$command" 2>&1)" || status=$?
    assert_equals 1 "$status"
    assert_contains "$output" 'Another dependency update is already running'
    assert_not_contains "$output" 'Linked worktrees are unsupported'
  done
  _release_dependency_update_lock
}

test_update_packages_refreshes_and_validates_all_pins_before_activation() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"

  sudo() { [[ "$*" == '-n -v' ]] || return 99; printf 'privilege\n' >> "$calls"; }
  _update_flake_inputs() {
    printf 'flake\n' >> "$calls"
    printf 'updated\n' > "$DOTFILES_DIR/flake.lock"
  }
  _update_all_dependency_pins() { printf 'pins\n' >> "$calls"; }
  _validate_dependency_update() { printf 'validate\n' >> "$calls"; }
  _approve_dependency_update() { printf 'approve\n' >> "$calls"; }
  _install_native_bootstrap_packages() { printf 'native:%s\n' "$1" >> "$calls"; }
  _home_manager_switch() { printf 'activate:%s:%s\n' "$1" "${DOTFILE_FLAKE_REF:-}" >> "$calls"; }
  _install_arch_service_state_backup() { printf 'service-state\n' >> "$calls"; }
  _update_pi_extensions() { printf 'extensions\n' >> "$calls"; }
  _sync_neovim() { printf 'neovim\n' >> "$calls"; }
  _publish_dependency_update() { printf 'publish:%s\n' "$1" >> "$calls"; }

  OS_RELEASE="$osrel" update_packages >/dev/null 2>&1

  assert_equals "$(printf 'privilege\nflake\npins\nvalidate\napprove\nnative:arch\nprivilege\nactivate:arch-server:path:%s\nservice-state\nextensions\nneovim\npublish:full' "$DOTFILES_DIR")" "$(<"$calls")"

  unset -f _update_flake_inputs _update_all_dependency_pins _validate_dependency_update _approve_dependency_update \
    _install_native_bootstrap_packages _home_manager_switch _install_arch_service_state_backup _update_pi_extensions \
    _sync_neovim _publish_dependency_update
}

test_update_packages_stops_on_missing_or_expired_privilege_before_activation() {
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release" calls fail_at sudo_calls status output
  printf 'ID=arch\n' > "$osrel"
  for fail_at in 1 2; do
    DOTFILES_DIR="$TEST_TMPDIR/update-$fail_at"
    _init_update_test_repo
    calls="$TEST_TMPDIR/privilege-$fail_at.log"
    : > "$calls"
    sudo_calls=0
    sudo() {
      [[ "$*" == '-n -v' ]] || return 99
      sudo_calls=$((sudo_calls + 1))
      printf 'privilege\n' >> "$calls"
      [[ "$sudo_calls" -lt "$fail_at" ]]
    }
    _update_flake_inputs() { printf 'refresh\n' >> "$calls"; printf 'updated\n' > "$DOTFILES_DIR/flake.lock"; }
    _update_all_dependency_pins() { :; }
    _validate_dependency_update() { :; }
    _approve_dependency_update() { :; }
    _install_native_bootstrap_packages() { :; }
    _home_manager_switch() { printf 'activate\n' >> "$calls"; }
    _install_arch_service_state_backup() { printf 'install\n' >> "$calls"; }
    _update_pi_extensions() { :; }
    _sync_neovim() { :; }
    _publish_dependency_update() { :; }
    status=0
    output="$(OS_RELEASE="$osrel" update_packages 2>&1)" || status=$?
    assert_equals 1 "$status"
    assert_not_contains "$(<"$calls")" activate
    assert_not_contains "$(<"$calls")" install
    assert_contains "$output" 'sudo -v'
    if [[ "$fail_at" == 1 ]]; then
      assert_not_contains "$(<"$calls")" refresh
    else
      assert_contains "$(<"$calls")" refresh
      assert_file_exists "$(_dependency_update_marker full)"
    fi
  done
}

test_arch_sudo_preflight_prompts_in_terminal_and_stops_on_cancellation() {
  TEST_TMPDIR="$TEST_TMPDIR" python3 "$REPO_DIR/tests/fixtures/arch-sudo-preflight.py"
}

test_update_ai_updates_only_ai_tools_and_configs() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/calls.log"
  printf 'ID=arch\n' > "$osrel"

  command() {
    if [[ "${1:-}" == "-v" ]]; then
      case "${2:-}" in
        nix|home-manager) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  _update_pi_release_package() {
    printf 'pi-update\n' >> "$calls"
    printf 'updated\n' > "$DOTFILES_DIR/pi-release.json"
  }
  _validate_dependency_update() {
    printf 'validate\n' >> "$calls"
  }
  _approve_dependency_update() {
    printf 'approve\n' >> "$calls"
  }
  _install_native_bootstrap_packages() {
    printf 'native\n' >> "$calls"
  }
  home-manager() {
    printf 'home-manager-switch\n' >> "$calls"
  }
  pi() {
    printf 'pi %s\n' "$*" >> "$calls"
  }
  _sync_neovim() {
    printf 'neovim-sync\n' >> "$calls"
  }
  _publish_dependency_update() {
    printf 'publish:%s\n' "$1" >> "$calls"
  }

  OS_RELEASE="$osrel" update_ai >/dev/null 2>&1

  assert_equals $'pi-update\nvalidate\napprove\nhome-manager-switch\npi update --extensions\npublish:ai' "$(<"$calls")"

  unset -f command _update_pi_release_package _validate_dependency_update \
    _approve_dependency_update _install_native_bootstrap_packages home-manager pi \
    _sync_neovim _publish_dependency_update
}

test_update_ai_validation_failure_stops_activation() {
  _init_update_test_repo
  DRY=false
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release" calls="$TEST_TMPDIR/ai-validation.log" status=0
  printf 'ID=arch\n' > "$osrel"
  _update_pi_release_package() { printf 'pi-update\n' >> "$calls"; printf 'updated\n' > "$DOTFILES_DIR/pi-release.json"; }
  _validate_dependency_update() { printf 'validate\n' >> "$calls"; return 1; }
  _home_manager_switch() { printf 'activate\n' >> "$calls"; }

  local output
  output="$(OS_RELEASE="$osrel" update_ai 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_equals $'pi-update\nvalidate' "$(<"$calls")"
  unset -f _update_pi_release_package _validate_dependency_update _home_manager_switch
}

test_update_ai_rechecks_validated_state_after_approval() {
  DRY=false
  mock_uname Linux
  local repo="$TEST_TMPDIR/ai-approval" old_dotfiles="$DOTFILES_DIR" osrel="$TEST_TMPDIR/os-release"
  local calls="$TEST_TMPDIR/ai-approval.log" source_repo status=0 output
  printf 'ID=arch\n' > "$osrel"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'old\n' > "$repo/managed"
  git -C "$repo" add managed
  git -C "$repo" commit -qm initial
  DOTFILES_DIR="$repo"
  source_repo="$repo"
  _refresh_ai_dependency_set() { printf 'validated\n' > "$DOTFILES_DIR/managed"; }
  _validate_dependency_update() { [[ "$(<"$DOTFILES_DIR/managed")" == validated ]]; }
  _approve_dependency_update() {
    printf 'tampered\n' > "$source_repo/managed"
    git -C "$source_repo" add managed
    git -C "$source_repo" commit -qm tampered
  }
  _home_manager_switch() { printf 'activate\n' >> "$calls"; }
  _update_pi_extensions() { :; }

  output="$(OS_RELEASE="$osrel" update_ai 2>&1)" || status=$?

  assert_equals "1" "$status"
  assert_equals "" "$(cat "$calls" 2>/dev/null || true)"
  assert_contains "$output" "Pending dependency update changed"
  unset -f _refresh_ai_dependency_set _validate_dependency_update _approve_dependency_update \
    _home_manager_switch _update_pi_extensions
  DOTFILES_DIR="$old_dotfiles"
}

test_update_ai_nixos_rebuilds_without_updating_flake() {
  DRY=true
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  _update_pi_release_package() { :; }

  local output
  output=$(OS_RELEASE="$osrel" update_ai 2>&1)

  assert_contains "$output" "Would run: sudo nixos-rebuild switch --flake path:$DOTFILES_DIR#testhost"
  assert_not_contains "$output" "nix flake update"

  unset -f _update_pi_release_package
}

test_update_ai_debian_and_mac_rebuild_without_updating_flake() {
  DRY=true
  _update_pi_release_package() { :; }

  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release" output
  printf 'ID=debian\n' > "$osrel"
  output="$(OS_RELEASE="$osrel" update_ai 2>&1)"
  assert_contains "$output" "home-manager switch --flake path:$DOTFILES_DIR#testuser@linux"
  assert_not_contains "$output" "nix flake update"

  mock_uname Darwin
  output="$(update_ai 2>&1)"
  assert_contains "$output" "darwin-rebuild switch --flake path:$DOTFILES_DIR#mac"
  assert_not_contains "$output" "nix flake update"

  unset -f _update_pi_release_package
}

test_update_packages_fails_unsupported_before_pin_update() {
  DRY=false
  mock_uname FreeBSD
  local calls="$TEST_TMPDIR/calls.log"
  : > "$calls"
  _update_pi_release_package() {
    printf 'pi-update\n' >> "$calls"
    printf 'updated\n' > "$DOTFILES_DIR/pi-release.json"
  }

  local output exit_code=0
  output=$(update_packages 2>&1) || exit_code=$?

  assert_equals "1" "$exit_code"
  assert_contains "$output" "Unsupported system: FreeBSD"
  assert_equals "" "$(<"$calls")"

  unset -f _update_pi_release_package
}
