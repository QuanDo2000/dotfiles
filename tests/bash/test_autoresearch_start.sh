#!/usr/bin/env bash
# Real Pi tool/session bridge with an offline provider; no optimization runs.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_helpers.sh"

test_autoresearch_start_uses_safe_session_transition() {
  assert_exit_code 0 python3 "$REPO_DIR/tests/fixtures/autoresearch-start.py" \
    "$TEST_TMPDIR" "$REPO_DIR/config/shared/ai/pi/autoresearch/index.ts" \
    "$REPO_DIR/tests/fixtures/autoresearch-start.ts"
}
