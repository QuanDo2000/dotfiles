#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

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

test_pi_seed_merge_engine_applies_live_only_nested_json() {
  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/pi_seed_merge.py"
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

  output="$(python3 "$script" "$live" "$seed" "$seed")"

  assert_contains "$output" "Applied Pi live config additions to tracked seed"
  assert_equals "live-model" "$(jq -r '.defaultModel' "$seed")"
  assert_equals "tracked-package" "$(jq -r '.packages[]' "$seed")"
  assert_equals "true" "$(jq -r '.custom.enabled' "$seed")"
  assert_equals "local-mcp" "$(jq -r '.mcpServers.local.command' "$seed")"
  assert_exit_code 0 jq empty "$seed"
  rm -rf "$tmp"
}
