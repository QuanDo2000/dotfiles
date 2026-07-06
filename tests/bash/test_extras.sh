#!/usr/bin/env bash
# Tests for scripts/extras.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh extras.sh
  # Provide a fake bin dir at the front of PATH so we can intercept git.
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

test_install_extras_is_nix_managed_noop() {
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_extras 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_extras should be a Nix-managed no-op ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "managed by Nix"
  assert_contains "$output" "Finished installing extras"
}
