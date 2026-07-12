#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_status_treats_primary_window_as_weekly_when_five_hour_limit_is_removed() {
  local output
  output="$(node - <<'NODE'
const { formatUsage } = require("./config/shared/ai/pi/codex-status.js");
process.stdout.write(formatUsage({
  plan_type: "pro",
  rate_limit: {
    primary_window: { used_percent: 42, limit_window_seconds: 604800, reset_after_seconds: 172800 }
  }
}));
NODE
)"

  assert_contains "$output" "5-hour limit: unavailable"
  assert_contains "$output" "Weekly limit: 42% used, resets in 2d 0h"
}

test_status_displays_both_windows_when_five_hour_limit_returns() {
  local output
  output="$(node - <<'NODE'
const { formatUsage } = require("./config/shared/ai/pi/codex-status.js");
process.stdout.write(formatUsage({
  rate_limit: {
    primary_window: { used_percent: 12, limit_window_seconds: 18000, reset_after_seconds: 3600 },
    secondary_window: { used_percent: 34, limit_window_seconds: 604800, reset_after_seconds: 172800 }
  }
}));
NODE
)"

  assert_contains "$output" "5-hour limit: 12% used, resets in 1h 0m"
  assert_contains "$output" "Weekly limit: 34% used, resets in 2d 0h"
}
