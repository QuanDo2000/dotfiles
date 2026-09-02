#!/usr/bin/env bash
# Local verification entrypoint coverage checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

test_check_script_runs_repo_verification() {
  local check_text flake_text
  check_text="$(<"$REPO_DIR/scripts/check.sh")"
  flake_text="$(<"$REPO_DIR/flake.nix")"

  assert_equals "1" "$(grep -c 'nix develop' <<< "$check_text")"
  assert_contains "$check_text" 'exec nix develop "$flake" -c env DOTFILE_CHECK_IN_DEV_SHELL=1 bash "$repo_dir/scripts/check.sh"'
  assert_contains "$check_text" 'run bash "$repo_dir/tests/bash/runner.sh"'
  assert_not_contains "$check_text" '--no-docker'
  assert_contains "$check_text" 'run pwsh "$repo_dir/tests/powershell/runner.ps1"'
  assert_contains "$check_text" 'command -v pwsh'
  assert_contains "$check_text" 'nix flake check "$flake" --no-build --all-systems'
  assert_contains "$check_text" 'darwinConfigurations.mac.system.drvPath'
  assert_contains "$check_text" 'homeConfigurations.\"$username@linux\".activationPackage.drvPath'
  assert_contains "$check_text" 'homeConfigurations.\"$username@arch-server\".activationPackage.drvPath'
  assert_contains "$check_text" 'flake="path:$repo_dir"'
  assert_contains "$check_text" '"$flake#obsidian-headless"'
  assert_contains "$check_text" '"$flake#pi-agent"'
  assert_contains "$check_text" 'if [[ "$(uname -s)" == "Linux" ]]'
  assert_contains "$check_text" 'nix build "${packages[@]}" --no-link'
  assert_contains "$check_text" 'run shellcheck'
  assert_contains "$flake_text" "pi-agent = final.callPackage ./packages/pi-agent.nix"
  assert_not_contains "$flake_text" "fff-nvim-backend"
  assert_contains "$flake_text" "packages.x86_64-linux.pi-agent = linuxPkgs.pi-agent"
  assert_contains "$flake_text" "packages.x86_64-linux.pi-extensions = linuxPkgs.pi-extensions"
  assert_contains "$flake_text" "devShells.aarch64-darwin.default"
  assert_contains "$flake_text" "jujutsu"
  assert_contains "$flake_text" "python3"
  assert_not_contains "$flake_text" "python-launcher"
  assert_contains "$flake_text" "shellcheck"
}

test_bash_runner_defaults_to_nix_environment() {
  local runner_text
  runner_text="$(<"$REPO_DIR/tests/bash/runner.sh")"
  assert_not_contains "$runner_text" 'docker build'
  assert_not_contains "$runner_text" 'Docker orchestration'
  assert_not_contains "$runner_text" '--no-docker'
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
