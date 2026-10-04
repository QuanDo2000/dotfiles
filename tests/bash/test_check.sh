#!/usr/bin/env bash
# Local verification entrypoint coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

# Substitute expensive tool boundaries, but execute the real gate and re-exec.
_check_fixture() {
  export CHECK_ROOT="$TEST_TMPDIR/check" CHECK_CALLS="$TEST_TMPDIR/check-calls"
  mkdir -p "$CHECK_ROOT/scripts" "$CHECK_ROOT/tests/bash" "$CHECK_ROOT/bin"
  cp "$REPO_DIR/scripts/check.sh" "$CHECK_ROOT/scripts/check.sh"
  : > "$CHECK_CALLS"
  printf 'printf "bash-tests\\n" >> "$CHECK_CALLS"\nexit "${CHECK_TEST_EXIT:-0}"\n' > "$CHECK_ROOT/tests/bash/runner.sh"
  cat > "$CHECK_ROOT/bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$CHECK_CALLS"
if [[ "$1" == develop ]]; then
  shift 3
  exec "$@"
fi
[[ "$1" != "${CHECK_FAIL:-}" ]] || exit 42
if [[ "$1" == eval && "$*" == *username* ]]; then printf 'test-user'; fi
if [[ "$1" == build ]]; then printf '/fixture-package\n'; fi
SH
  local tool
  for tool in pwsh shellcheck python3; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$CHECK_CALLS"\n' "$tool" > "$CHECK_ROOT/bin/$tool"
  done
  chmod +x "$CHECK_ROOT/bin/"*
}

test_check_script_runs_repo_verification() {
  _check_fixture
  assert_exit_code 0 env -u DOTFILE_CHECK_IN_DEV_SHELL PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  local calls
  calls="$(<"$CHECK_CALLS")"
  assert_contains "$calls" "nix develop path:$CHECK_ROOT -c"
  assert_contains "$calls" 'bash-tests'
  assert_contains "$calls" 'pwsh '
  assert_contains "$calls" "nix flake check path:$CHECK_ROOT --no-build --all-systems"
  assert_contains "$calls" "path:$CHECK_ROOT#pi-extensions"
  if [[ "$(uname -s)" == Linux ]]; then
    assert_contains "$calls" 'test-user@linux'
    assert_contains "$calls" 'test-user@arch-server'
    assert_contains "$calls" "path:$CHECK_ROOT#pi-agent"
    assert_contains "$calls" 'python3 '
    assert_equals 1 "$(grep -c '^nix build .*#hyprsunset-status' "$CHECK_CALLS")"
  else
    assert_contains "$calls" 'darwinConfigurations.mac.system.drvPath'
  fi
  assert_contains "$calls" 'shellcheck '
}

test_check_script_stops_on_failed_tests_or_build() {
  _check_fixture
  assert_exit_code 23 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_TEST_EXIT=23 PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_not_contains "$(<"$CHECK_CALLS")" 'nix flake check'
  : > "$CHECK_CALLS"
  assert_exit_code 42 env DOTFILE_CHECK_IN_DEV_SHELL=1 CHECK_FAIL=build PATH="$CHECK_ROOT/bin:$PATH" bash "$CHECK_ROOT/scripts/check.sh"
  assert_not_contains "$(<"$CHECK_CALLS")" 'shellcheck '
}

test_bash_runner_accepts_multiple_test_files() {
  local fixtures="$TEST_TMPDIR/fixtures" output
  mkdir -p "$fixtures"
  printf 'test_one() { :; }\n' > "$fixtures/test_one.sh"
  printf 'test_two() { :; }\n' > "$fixtures/test_two.sh"

  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_one.sh" "$fixtures/test_two.sh" 2>&1)"

  assert_contains "$output" "--- test_one.sh ---"
  assert_contains "$output" "--- test_two.sh ---"
}

test_bash_runner_discovers_tests_without_compgen_and_fails_empty_files() {
  local bash_env="$TEST_TMPDIR/bash-env" fixture="$TEST_TMPDIR/test_fixture.sh" output status=0
  printf 'enable -n compgen 2>/dev/null || true\n' > "$bash_env"
  printf 'test_body() { :; }\n' > "$fixture"

  output="$(BASH_ENV="$bash_env" bash "$REPO_DIR/tests/bash/runner.sh" "$fixture" 2>&1)" || status=$?
  assert_equals 0 "$status"
  assert_contains "$output" '1 passed, 0 failed, 1 total'

  status=0
  : > "$fixture"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixture" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  no test_* functions found'
}

test_bash_runner_fails_setup_and_teardown_errors() {
  local fixtures="$TEST_TMPDIR/fixtures" output status=0
  mkdir -p "$fixtures"
  printf 'setup() { false; :; }\nteardown() { :; }\ntest_body() { :; }\n' > "$fixtures/test_setup.sh"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_setup.sh" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  test_body'

  status=0
  printf 'teardown() { return 43; }\ntest_body() { :; }\n' > "$fixtures/test_teardown.sh"
  output="$(bash "$REPO_DIR/tests/bash/runner.sh" "$fixtures/test_teardown.sh" 2>&1)" || status=$?
  assert_equals 1 "$status"
  assert_contains "$output" 'FAIL  test_body'
}

test_bash_runner_uses_repo_working_directory() {
  local output status=0
  output="$(cd / && bash "$REPO_DIR/tests/bash/runner.sh" test_codex_status.sh 2>&1)" || status=$?
  assert_equals 0 "$status"
  assert_contains "$output" '0 failed'
}
