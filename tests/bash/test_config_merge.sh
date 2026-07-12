#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_codex_seed_merge_writes_atomically() {
  local script
  script="$(<"$REPO_DIR/scripts/codex_seed_merge.py")"

  assert_contains "$script" "tempfile.mkstemp"
  assert_contains "$script" "os.replace"
}

test_codex_seed_merge_engine_applies_live_only_nested_toml() {
  if ! python3 -c 'import tomllib' 2>/dev/null; then
    printf '  SKIP  Codex merge test requires Python 3.11+\n'
    return
  fi

  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/codex_seed_merge.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "gpt-5.5"
approval_policy = "on-request"

[features]
memories = true
multi_agent = true

[projects."/home/quando/dotfiles"]
trust_level = "trusted"

[hooks]
SessionStart = [{ matcher = "startup", hooks = [{ type = "command", command = "echo hi" }] }]
EOF

  cat > "$seed" <<'EOF'
model = "gpt-5.5"

[features]
memories = true
EOF

  output="$(python3 "$script" "$live" "$seed" "$seed")"

  assert_contains "$output" "Applied Codex live config additions to tracked seed"
  assert_contains "$(<"$seed")" 'approval_policy = "on-request"'
  assert_contains "$(<"$seed")" "multi_agent = true"
  assert_contains "$(<"$seed")" '[projects."/home/quando/dotfiles"]'
  assert_not_contains "$(<"$seed")" '[hooks]'
  assert_exit_code 0 python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$seed"
  rm -rf "$tmp"
}

test_lazyvim_three_way_merge_preserves_tracked_and_live_changes() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/lazyvim_seed_merge.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"extras":["stale"],"news":{},"version":7}' > "$live"
  printf '%s\n' '{"extras":["base"],"news":{},"version":8}' > "$seed"
  local output
  output="$(python3 "$script" "$live" "$seed" "$seed" "$base")"
  assert_contains "$output" "Applied LazyVim config changes to live config and tracked seed"
  assert_equals '["base"]' "$(jq -c '.extras' "$live")"

  # A live removal wins when the tracked seed has not changed.
  printf '%s\n' '{"extras":[],"news":{},"version":8}' > "$live"
  python3 "$script" "$live" "$seed" "$seed" "$base"
  assert_equals '[]' "$(jq -c '.extras' "$seed")"

  # A newly pulled tracked change wins over stale live state.
  printf '%s\n' '{"extras":["pulled"],"news":{},"version":9}' > "$seed"
  python3 "$script" "$live" "$seed" "$seed" "$base"
  assert_equals '["pulled"]' "$(jq -c '.extras' "$live")"
  assert_equals '9' "$(jq -r '.version' "$live")"

  # Independent nested changes survive on both sides.
  cp "$seed" "$base"
  printf '%s\n' '{"extras":["pulled"],"news":{"live":"yes"},"version":9}' > "$live"
  printf '%s\n' '{"extras":["pulled"],"news":{"tracked":"yes"},"version":9}' > "$seed"
  python3 "$script" "$live" "$seed" "$seed" "$base"
  assert_equals 'yes' "$(jq -r '.news.live' "$seed")"
  assert_equals 'yes' "$(jq -r '.news.tracked' "$live")"
  assert_equals '["live","tracked"]' "$(jq -c '.news | keys_unsorted' "$live")"
  rm -rf "$tmp"
}

test_lazyvim_merge_recovers_corrupt_baseline_and_reports_read_only_seed() {
  local tmp script live seed base output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/lazyvim_seed_merge.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"extras":["live"]}' > "$live"
  printf '%s\n' '{"extras":["seed"]}' > "$seed"
  printf '%s\n' '{broken' > "$base"

  output="$(python3 "$script" "$live" "$seed" '' "$base")"

  assert_contains "$output" "tracked seed was not writable"
  assert_equals '["seed"]' "$(jq -c '.extras' "$live")"
  assert_exit_code 0 jq empty "$base"
  rm -rf "$tmp"
}

test_lazyvim_merge_preserves_seed_permissions() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/lazyvim_seed_merge.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"extras":[]}' > "$live"
  cp "$live" "$seed"
  chmod 0644 "$seed"

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "644" "$(python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$seed")"
  rm -rf "$tmp"
}

test_pi_seed_merge_engine_applies_live_only_nested_json() {
  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/json_seed_merge.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"

  cat > "$live" <<'EOF'
{
  "defaultModel": "live-model",
  "packages": ["runtime-package"],
  "custom": {"enabled": true},
  "mcpServers": {"local": {"command": "local-mcp"}}
}
EOF
  cat > "$seed" <<'EOF'
{
  "defaultModel": "tracked-model",
  "packages": ["tracked-package"],
  "mcpServers": {}
}
EOF

  output="$(python3 "$script" "$live" "$seed" "$seed" Pi defaultModel)"

  assert_contains "$output" "Applied Pi config changes to tracked seed"
  assert_equals "live-model" "$(jq -r '.defaultModel' "$seed")"
  assert_equals "tracked-package" "$(jq -r '.packages[]' "$seed")"
  assert_equals "true" "$(jq -r '.custom.enabled' "$seed")"
  assert_equals "local-mcp" "$(jq -r '.mcpServers.local.command' "$seed")"
  assert_exit_code 0 jq empty "$seed"
  rm -rf "$tmp"
}
