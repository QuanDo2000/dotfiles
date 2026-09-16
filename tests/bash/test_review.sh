#!/usr/bin/env bash
# Exact review targets and real offline Pi SDK/tool dispatch.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() { init_test_env; }
teardown() { cleanup_test_env; }

test_review_targets_require_clean_exact_commits() {
  assert_exit_code 0 node --test "$REPO_DIR/tests/fixtures/review-target.test.mjs"
}

test_review_sdk_isolation_and_tool_dispatch() {
  assert_exit_code 0 python3 "$REPO_DIR/tests/fixtures/review-integration.py"
}
