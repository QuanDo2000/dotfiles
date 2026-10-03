#!/usr/bin/env bash
# Run the update gate with disposable Git state and expensive tool substitutes.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  export UPDATE_ROOT="$TEST_TMPDIR/repo" UPDATE_CALLS="$TEST_TMPDIR/calls"
  mkdir -p "$UPDATE_ROOT/scripts" "$UPDATE_ROOT/tests/bash" "$UPDATE_ROOT/bin"
  cp "$REPO_DIR/scripts/platform.sh" "$UPDATE_ROOT/scripts/"
  if [[ -f "$REPO_DIR/scripts/check-update.sh" ]]; then
    cp "$REPO_DIR/scripts/check-update.sh" "$UPDATE_ROOT/scripts/"
  fi
  printf 'printf "full-gate\\n" >> "$UPDATE_CALLS"\n' > "$UPDATE_ROOT/scripts/check.sh"
  printf 'printf "tests %%s\\n" "$*" >> "$UPDATE_CALLS"\nprintf "test-env %%s\\n" "${UPDATE_CANDIDATE_ENV:-old}" >> "$UPDATE_CALLS"\nexit "${UPDATE_TEST_EXIT:-0}"\n' > "$UPDATE_ROOT/tests/bash/runner.sh"
  cat > "$UPDATE_ROOT/bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$UPDATE_CALLS"
[[ "$1" != "${UPDATE_FAIL:-}" ]] || exit 42
if [[ "$1" == develop ]]; then
  export UPDATE_CANDIDATE_ENV=candidate
  shift 3
  exec "$@"
fi
if [[ "$1" == eval && "$*" == *--file* ]]; then printf 'fixture'; fi
if [[ "$1" == build ]]; then printf '/fixture-package\n'; fi
SH
  printf '#!/usr/bin/env bash\nprintf "oracle %%s\\n" "$HYPRSUNSET_CANDIDATE" >> "$UPDATE_CALLS"\n' > "$UPDATE_ROOT/bin/python3"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${UPDATE_UNAME:-Linux}"\n' > "$UPDATE_ROOT/bin/uname"
  chmod +x "$UPDATE_ROOT/bin/"*
  printf 'ID=debian\n' > "$TEST_TMPDIR/os-release"
  printf 'fixture-kernel\n' > "$TEST_TMPDIR/kernel"
  export OS_RELEASE="$TEST_TMPDIR/os-release" KERNEL_RELEASE_FILE="$TEST_TMPDIR/kernel" WSL_DISTRO_NAME=
  git -C "$UPDATE_ROOT" init -q
  git -C "$UPDATE_ROOT" config user.email test@example.com
  git -C "$UPDATE_ROOT" config user.name Test
  git -C "$UPDATE_ROOT" add scripts tests bin
  git -C "$UPDATE_ROOT" commit -qm initial
  : > "$UPDATE_CALLS"
}
teardown() { cleanup_test_env; }

_update_change() { mkdir -p "$(dirname "$UPDATE_ROOT/$1")"; printf 'changed\n' > "$UPDATE_ROOT/$1"; }
_update_gate() { PATH="$UPDATE_ROOT/bin:$PATH" bash "$UPDATE_ROOT/scripts/check-update.sh" "$@"; }

test_ai_update_gate_excludes_unrelated_checks() {
  _update_change packages/pi-agent.nix
  assert_exit_code 0 _update_gate ai
  local calls
  calls="$(<"$UPDATE_CALLS")"
  assert_contains "$calls" 'test_pi_compaction_patch.sh'
  assert_contains "$calls" '#pi-agent'
  assert_contains "$calls" 'homeConfigurations."fixture@linux"'
  assert_not_contains "$calls" 'test_neovim.sh'
  assert_not_contains "$calls" 'test_home_profiles.sh'
  assert_not_contains "$calls" '#obsidian-headless'
  assert_not_contains "$calls" 'full-gate'
}

test_update_gate_checks_changed_dependencies_and_rebased_commit() {
  _update_change config/shared/config/nvim/lazy-lock.json
  git -C "$UPDATE_ROOT" add config
  git -C "$UPDATE_ROOT" commit -qm pins
  assert_exit_code 0 _update_gate full HEAD^
  assert_contains "$(<"$UPDATE_CALLS")" 'test_neovim.sh'
  assert_not_contains "$(<"$UPDATE_CALLS")" '#obsidian-headless'
}

test_update_gate_flake_changes_cover_custom_packages_and_roles() {
  _update_change flake.lock
  assert_exit_code 0 _update_gate full
  local calls
  calls="$(<"$UPDATE_CALLS")"
  assert_contains "$calls" "nix develop path:$UPDATE_ROOT -c"
  assert_contains "$calls" 'test-env candidate'
  assert_not_contains "$calls" 'test-env old'
  assert_contains "$calls" 'test_home_profiles.sh'
  assert_contains "$calls" 'test_neovim.sh'
  assert_contains "$calls" '#pi-extensions'
  assert_contains "$calls" '#obsidian-headless'
  assert_contains "$calls" '#hyprsunset-status'
  assert_contains "$calls" 'oracle /fixture-package/bin/hyprsunset-status'
}

test_update_gate_selects_native_profiles() {
  printf 'ID=arch\n' > "$OS_RELEASE"
  assert_exit_code 0 _update_gate full
  assert_contains "$(<"$UPDATE_CALLS")" 'fixture@arch-server'
  : > "$UPDATE_CALLS"
  printf 'ID=nixos\n' > "$OS_RELEASE"
  assert_exit_code 0 _update_gate full
  assert_contains "$(<"$UPDATE_CALLS")" 'nixosConfigurations."fixture"'
  : > "$UPDATE_CALLS"
  printf 'Microsoft WSL\n' > "$KERNEL_RELEASE_FILE"
  assert_exit_code 0 _update_gate full
  assert_contains "$(<"$UPDATE_CALLS")" 'nixosConfigurations."fixture-wsl"'
  : > "$UPDATE_CALLS"
  UPDATE_UNAME=Darwin assert_exit_code 0 _update_gate full
  assert_contains "$(<"$UPDATE_CALLS")" 'darwinConfigurations.mac'
}

test_update_gate_unknown_changes_fall_back_to_full_checks() {
  _update_change scripts/packages.sh
  assert_exit_code 0 _update_gate ai
  assert_equals full-gate "$(<"$UPDATE_CALLS")"
}

test_update_gate_failures_stop_validation() {
  _update_change packages/pi-agent.nix
  assert_exit_code 23 env UPDATE_TEST_EXIT=23 PATH="$UPDATE_ROOT/bin:$PATH" bash "$UPDATE_ROOT/scripts/check-update.sh" ai
  assert_not_contains "$(<"$UPDATE_CALLS")" 'nix eval'
  : > "$UPDATE_CALLS"
  assert_exit_code 42 env UPDATE_FAIL=build PATH="$UPDATE_ROOT/bin:$PATH" bash "$UPDATE_ROOT/scripts/check-update.sh" ai
  assert_exit_code 1 _update_gate invalid
  assert_exit_code 1 _update_gate ai bad-revision
  : > "$UPDATE_CALLS"
  _update_change flake.lock
  assert_exit_code 42 env UPDATE_FAIL=develop PATH="$UPDATE_ROOT/bin:$PATH" bash "$UPDATE_ROOT/scripts/check-update.sh" full
  assert_not_contains "$(<"$UPDATE_CALLS")" 'tests '
}
