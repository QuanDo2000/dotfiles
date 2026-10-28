#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() { init_test_env; }
teardown() { cleanup_test_env; }

test_calendar_retention_destructive_boundaries() {
  assert_exit_code 0 python3 "$REPO_DIR/tests/python/test_qbittorrent_calendar_retention.py"
}
