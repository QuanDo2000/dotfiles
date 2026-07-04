#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

test_opencode_shared_config_does_not_disable_self_update() {
  local config="$REPO_DIR/config/shared/ai/opencode/opencode.json"

  assert_equals "false" "$(jq -r 'has("autoupdate")' "$config")"
}

test_opencode_nixos_config_disables_self_update() {
  local config="$REPO_DIR/config/nixos/ai/opencode/opencode.json"

  assert_equals "false" "$(jq -r '.autoupdate' "$config")"
}
