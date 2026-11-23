#!/usr/bin/env bash
# Update validation keeps candidate-shell and deployed-role boundaries.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_update_validation_enters_candidate_gate_and_propagates_failure() {
  mkdir -p "$DOTFILES_DIR/scripts"
  cat > "$DOTFILES_DIR/scripts/check.sh" <<'SH'
printf '%s:%s\n' "${DOTFILE_CHECK_IN_DEV_SHELL:-unset}" "${DOTFILE_CHECK_DEPLOYED_ROLE:-unset}" > "$TEST_TMPDIR/gate-env"
exit "${GATE_STATUS:-0}"
SH
  export TEST_TMPDIR
  DOTFILE_CHECK_IN_DEV_SHELL=1 _validate_dependency_update ai
  assert_equals 'unset:1' "$(<"$TEST_TMPDIR/gate-env")"
  local output status=0
  output="$(GATE_STATUS=42 _validate_dependency_update full 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'Dependency checks failed; refusing activation'
}

test_update_gate_evaluates_deployed_role() {
  local osrel="$TEST_TMPDIR/os-release" kernel="$TEST_TMPDIR/kernel" calls="$TEST_TMPDIR/nix-calls"
  export OS_RELEASE="$osrel" KERNEL_RELEASE_FILE="$kernel" DOTFILE_CHECK_DEPLOYED_ROLE=1 WSL_DISTRO_NAME=
  printf 'normal\n' > "$kernel"
  # shellcheck source=../../scripts/check_nix.sh
  source "$REPO_DIR/scripts/check_nix.sh"
  nix() {
    printf '%s\n' "$*" >> "$calls"
    if [[ "$*" == *--file*hostName* ]]; then printf 'fixture'; return 0; fi
    if [[ "$*" == *--file*username* ]]; then printf 'user'; return 0; fi
    [[ "${NIX_FAIL:-0}" != 1 ]] || return 42
  }
  local platform expected
  for platform in nixos wsl debian arch mac; do
    printf 'normal\n' > "$kernel"
    mock_uname Linux
    case "$platform" in
      nixos) printf 'ID=nixos\n' > "$osrel"; expected='nixosConfigurations."fixture"' ;;
      wsl) printf 'ID=nixos\n' > "$osrel"; printf 'microsoft\n' > "$kernel"; expected='nixosConfigurations."fixture-wsl"' ;;
      debian) printf 'ID=debian\n' > "$osrel"; expected='homeConfigurations."user@linux"' ;;
      arch) printf 'ID=arch\n' > "$osrel"; expected='homeConfigurations."user@arch-server"' ;;
      mac) mock_uname Darwin; expected='darwinConfigurations.mac' ;;
    esac
    : > "$calls"
    assert_exit_code 0 check_deployed_role
    assert_contains "$(<"$calls")" "$expected"
  done
  NIX_FAIL=1 assert_exit_code 42 check_deployed_role
}
