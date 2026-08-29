#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_pi_seed_merge_distinguishes_booleans_from_numbers() {
  local tmp script
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  printf '%s\n' '{"value":1}' >"$tmp/live.json"
  printf '%s\n' '{"value":true}' >"$tmp/seed.json"
  printf '%s\n' '{"value":1}' >"$tmp/base.json"

  python3 "$script" "$tmp/live.json" "$tmp/seed.json" "$tmp/seed.json" "$tmp/base.json" >/dev/null
  python3 - "$tmp/live.json" "$tmp/seed.json" "$tmp/base.json" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as file:
        value = json.load(file)["value"]
    assert value is True, f"{path} did not preserve boolean type: {value!r}"
PY
  rm -rf "$tmp"
}

test_pi_seed_merge_rejects_corrupt_baseline_without_writes() {
  local tmp script before_live before_seed before_base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  printf '%s\n' '{"kept":true,"runtimeOnly":true}' >"$tmp/live.json"
  printf '%s\n' '{"kept":true}' >"$tmp/seed.json"
  printf '%s\n' '{invalid' >"$tmp/base.json"
  before_live="$(<"$tmp/live.json")"
  before_seed="$(<"$tmp/seed.json")"
  before_base="$(<"$tmp/base.json")"

  if python3 "$script" "$tmp/live.json" "$tmp/seed.json" "$tmp/seed.json" "$tmp/base.json" >/dev/null 2>&1; then
    printf 'corrupt Pi baseline should fail closed\n' >&2
    rm -rf "$tmp"
    return 1
  fi
  assert_equals "$before_live" "$(<"$tmp/live.json")"
  assert_equals "$before_seed" "$(<"$tmp/seed.json")"
  assert_equals "$before_base" "$(<"$tmp/base.json")"
  rm -rf "$tmp"
}

test_pi_seed_merge_writes_live_before_writable_seed() {
  python3 - "$REPO_DIR/scripts/seed_merge/pi.py" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
live = script.index("write_json(live_path")
seed = script.index("write_json(apply_path")
assert live < seed, "live CAS must succeed before writable seed commit"
PY
}

test_json_atomic_write_rejects_changed_destination() {
  local tmp
  tmp="$(mktemp -d)"
  PYTHONPATH="$REPO_DIR/scripts/seed_merge" python3 - "$tmp/live.json" <<'PY'
import json
import sys

from common import write_json

path = sys.argv[1]
with open(path, "w", encoding="utf-8") as file:
    json.dump({"value": 2}, file)
try:
    write_json(path, {"value": 3}, prefix=".json-test-", expected={"value": 1})
except RuntimeError as error:
    assert "changed during merge" in str(error)
else:
    raise AssertionError("changed destination was overwritten")
with open(path, encoding="utf-8") as file:
    assert json.load(file) == {"value": 2}
PY
  rm -rf "$tmp"
}

test_codex_seed_merge_writes_atomically() {
  local script
  script="$(<"$REPO_DIR/scripts/seed_merge/codex.py")"

  assert_contains "$script" "tempfile.mkstemp"
  assert_contains "$script" "os.replace"
}

test_codex_seed_merge_round_trips_toml_types() {
  local tmp script
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  cat >"$tmp/live.toml" <<'EOF'
message = "line 1\nline 2"
controls = "\b\f\u007f"
when = 2026-08-15T12:34:56Z
ratio = inf
negative = -inf
unknown = nan
EOF
  : >"$tmp/seed.toml"
  python3 "$script" "$tmp/live.toml" "$tmp/seed.toml" "" >/dev/null
  python3 - "$tmp/live.toml" <<'PY'
import math
import sys
import tomllib
value = tomllib.loads(open(sys.argv[1], 'rb').read().decode())
assert value['message'] == 'line 1\nline 2'
assert value['controls'] == '\b\f\x7f'
assert value['when'].year == 2026
assert math.isinf(value['ratio']) and value['ratio'] > 0
assert math.isinf(value['negative']) and value['negative'] < 0
assert math.isnan(value['unknown'])
PY
  rm -rf "$tmp"
}

test_codex_seed_merge_engine_applies_live_only_nested_toml() {
  if ! python3 -c 'import tomllib' 2>/dev/null; then
    printf '  SKIP  Codex merge test requires Python 3.11+\n'
    return
  fi

  local tmp script live seed output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "gpt-5.5"
approval_policy = "on-request"

[features]
memories = true
multi_agent = true

[marketplaces.local-runtime]
source = "/tmp/marketplace"

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
  assert_not_contains "$(<"$seed")" '[marketplaces.local-runtime]'
  assert_not_contains "$(<"$seed")" '[projects."/home/quando/dotfiles"]'
  assert_not_contains "$(<"$seed")" '[hooks]'
  assert_exit_code 0 python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$seed"
  rm -rf "$tmp"
}


test_codex_seed_merge_read_only_mode_preserves_live_runtime_state() {
  local tmp script live seed before output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/windows-seed.toml"

  cat > "$live" <<'EOF'
model = "live"

[mcp_servers.node_repl]
command = "C:\\Users\\Quan\\runtime\\node_repl.exe"

[projects."C:\\Users\\Quan\\project"]
trust_level = "trusted"
EOF

  cat > "$seed" <<'EOF'
model = "tracked"

EOF

  before="$(sha256sum "$seed")"
  output="$(python3 "$script" "$live" "$seed" '')"

  assert_contains "$output" "$seed"
  assert_equals "$before" "$(sha256sum "$seed")"
  assert_equals "tracked" "$(python3 -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["model"])' "$live")"
  assert_contains "$(<"$live")" '[mcp_servers.node_repl]'
  assert_contains "$(<"$live")" '[projects."C:\\Users\\Quan\\project"]'
  rm -rf "$tmp"
}


test_codex_seed_merge_removes_retired_ponytail_marketplace() {
  local tmp script live seed
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "live"

[marketplaces.ponytail]
source_type = "git"
source = "https://github.com/DietrichGebert/ponytail.git"

[marketplaces.openai-bundled]
source_type = "local"
source = "/tmp/openai-bundled"

[plugins."ponytail@ponytail"]
enabled = true

[plugins."sites@openai-bundled"]
enabled = true

[hooks.state."ponytail@ponytail:hooks/claude-codex-hooks.json:session_start:0:0"]
trusted_hash = "sha256:retired"

[hooks.state."other@local:hooks/hooks.json:session_start:0:0"]
trusted_hash = "sha256:keep"
EOF

  printf '%s\n' 'model = "tracked"' > "$seed"
  python3 "$script" "$live" "$seed" '' >/dev/null

  assert_not_contains "$(<"$live")" '[marketplaces.ponytail]'
  assert_not_contains "$(<"$live")" '[plugins."ponytail@ponytail"]'
  assert_not_contains "$(<"$live")" 'ponytail@ponytail:hooks/'
  assert_contains "$(<"$live")" '[marketplaces.openai-bundled]'
  assert_contains "$(<"$live")" '[plugins."sites@openai-bundled"]'
  assert_contains "$(<"$live")" 'other@local:hooks/'
  rm -rf "$tmp"
}


test_codex_seed_merge_removes_retired_fff_mcp() {
  local tmp script live seed
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "live"

[mcp_servers.fff]
command = "fff-mcp-agent"

[mcp_servers.custom]
command = "custom-mcp"
EOF

  cat > "$seed" <<'EOF'
model = "tracked"

[mcp_servers.fff]
command = "fff-mcp-agent"
EOF

  python3 "$script" "$live" "$seed" "$seed" >/dev/null

  assert_not_contains "$(<"$live")" '[mcp_servers.fff]'
  assert_not_contains "$(<"$seed")" '[mcp_servers.fff]'
  assert_contains "$(<"$live")" '[mcp_servers.custom]'
  assert_contains "$(<"$seed")" '[mcp_servers.custom]'
  rm -rf "$tmp"
}


test_codex_seed_merge_removes_generated_codebase_memory_hook() {
  local tmp script live seed
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "live"

[[hooks.SessionStart]]
matcher = "startup|resume|clear|compact"
hooks = [{ type = "command", command = "codebase-memory-mcp hook-augment" }]

[[hooks.SessionStart]]
matcher = "startup"
hooks = [{ type = "command", command = "custom-hook" }]
EOF

  printf '%s\n' 'model = "tracked"' > "$seed"
  python3 "$script" "$live" "$seed" '' >/dev/null

  assert_not_contains "$(<"$live")" 'codebase-memory-mcp hook-augment'
  assert_contains "$(<"$live")" 'command = "custom-hook"'
  rm -rf "$tmp"
}


test_codex_seed_merge_engine_applies_tracked_additions_to_live() {
  local tmp script live seed
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/codex.py"
  live="$tmp/live.toml"
  seed="$tmp/seed.toml"

  cat > "$live" <<'EOF'
model = "gpt-5.5"

[hooks.state]
live_only = "keep"
EOF

  cat > "$seed" <<'EOF'
model = "gpt-5.5"

EOF

  python3 "$script" "$live" "$seed" "$seed" >/dev/null

  assert_contains "$(<"$live")" 'live_only = "keep"'
  assert_exit_code 0 python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$live"
  rm -rf "$tmp"
}

test_home_manager_pi_merge_uses_per_file_baselines() {
  local home
  home="$(<"$REPO_DIR/config/home.nix")"

  assert_contains "$home" 'base="$HOME/.local/state/dotfiles/pi/$name"'
  assert_contains "$home" 'pi.py" "$target" "$source" "$apply_seed" "$base"'
  assert_not_contains "$home" "(\$live * \$seed)"
}

test_pi_three_way_merge_does_not_rewrite_unchanged_files() {
  local tmp script live seed base before
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"settings":["one","two"]}' > "$live"
  cp "$live" "$seed"
  cp "$live" "$base"
  before="$(sha256sum "$live" "$seed" "$base")"

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "$before" "$(sha256sum "$live" "$seed" "$base")"
  rm -rf "$tmp"
}

test_pi_three_way_merge_preserves_live_changes_and_tracked_deletions() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"removed":true,"value":"base","nested":{"common":"base","live":"yes"}}' > "$live"
  printf '%s\n' '{"value":"tracked","nested":{"common":"base"}}' > "$seed"
  printf '%s\n' '{"removed":true,"value":"base","nested":{"common":"base"}}' > "$base"

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "false" "$(jq 'has("removed")' "$live")"
  assert_equals "tracked" "$(jq -r '.value' "$live")"
  assert_equals "yes" "$(jq -r '.nested.live' "$seed")"
  assert_equals "$(jq -cS . "$seed")" "$(jq -cS . "$base")"
  rm -rf "$tmp"
}

test_pi_three_way_merge_keeps_live_changes_pending_when_seed_is_read_only() {
  local tmp script live seed base before
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  printf '%s\n' '{"tracked":"old","liveOnly":true,"lastChangelogVersion":"0.84.1"}' > "$live"
  printf '%s\n' '{"tracked":"new"}' > "$seed"
  printf '%s\n' '{"tracked":"old"}' > "$base"
  before="$(sha256sum "$seed")"

  python3 "$script" "$live" "$seed" '' "$base" >/dev/null
  python3 "$script" "$live" "$seed" '' "$base" >/dev/null

  assert_equals "$before" "$(sha256sum "$seed")"
  assert_equals "new" "$(jq -r '.tracked' "$live")"
  assert_equals "true" "$(jq -r '.liveOnly' "$live")"
  assert_equals "0.84.1" "$(jq -r '.lastChangelogVersion' "$live")"
  assert_equals "false" "$(jq 'has("liveOnly")' "$base")"
  assert_equals "false" "$(jq 'has("lastChangelogVersion")' "$base")"
  rm -rf "$tmp"
}

test_pi_seed_merge_removes_retired_codebase_memory_without_baseline() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  cat > "$live" <<'EOF'
{
  "mcpServers": {
    "codebaseMemory": {"command": "codebase-memory-mcp", "lifecycle": "eager"},
    "custom": {"command": "custom-mcp"}
  }
}
EOF
  printf '%s\n' '{"mcpServers":{}}' > "$seed"

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "false" "$(jq '.mcpServers | has("codebaseMemory")' "$live")"
  assert_equals "false" "$(jq '.mcpServers | has("codebaseMemory")' "$seed")"
  assert_equals "custom-mcp" "$(jq -r '.mcpServers.custom.command' "$live")"
  assert_equals "custom-mcp" "$(jq -r '.mcpServers.custom.command' "$seed")"
  rm -rf "$tmp"
}

test_pi_seed_merge_engine_applies_live_only_nested_json() {
  local tmp script live seed base output
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

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

  output="$(python3 "$script" "$live" "$seed" "$seed" "$base")"

  assert_contains "$output" "Applied Pi config changes to tracked seed"
  assert_equals "live-model" "$(jq -r '.defaultModel' "$seed")"
  assert_equals "tracked-package" "$(jq -r '.packages[]' "$seed")"
  assert_equals "true" "$(jq -r '.custom.enabled' "$seed")"
  assert_equals "local-mcp" "$(jq -r '.mcpServers.local.command' "$seed")"
  assert_exit_code 0 jq empty "$seed"
  rm -rf "$tmp"
}

test_pi_seed_merge_removes_redundant_defaults_from_live_and_seed() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  cat > "$live" <<'EOF'
{
  "enableSkillCommands": true,
  "skills": ["~/.agents/skills"],
  "lastChangelogVersion": "0.84.1",
  "editorPaddingX": 0,
  "outputPad": 1,
  "transport": "auto"
}
EOF
  cat > "$seed" <<'EOF'
{
  "enableSkillCommands": true,
  "skills": ["~/.agents/skills"],
  "lastChangelogVersion": "0.80.6",
  "editorPaddingX": 0,
  "outputPad": 1,
  "transport": "auto"
}
EOF

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "false" "$(jq 'has("enableSkillCommands")' "$live")"
  assert_equals "false" "$(jq 'has("skills")' "$live")"
  assert_equals "true" "$(jq 'has("lastChangelogVersion")' "$live")"
  assert_equals "false" "$(jq 'has("editorPaddingX")' "$live")"
  assert_equals "false" "$(jq 'has("outputPad")' "$live")"
  assert_equals "false" "$(jq 'has("transport")' "$live")"
  assert_equals "[]" "$(jq -c 'keys' "$seed")"
  rm -rf "$tmp"
}

test_pi_seed_merge_preserves_nondefault_live_settings() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  cat > "$live" <<'EOF'
{
  "enableSkillCommands": false,
  "skills": ["~/custom-skills"],
  "editorPaddingX": 2,
  "outputPad": 0,
  "transport": "sse"
}
EOF
  printf '{}\n' > "$seed"

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "false" "$(jq -r '.enableSkillCommands' "$seed")"
  assert_equals "~/custom-skills" "$(jq -r '.skills[]' "$seed")"
  assert_equals "2" "$(jq -r '.editorPaddingX' "$seed")"
  assert_equals "0" "$(jq -r '.outputPad' "$seed")"
  assert_equals "sse" "$(jq -r '.transport' "$seed")"
  rm -rf "$tmp"
}

test_pi_seed_merge_keeps_tracked_subagents_authoritative() {
  local tmp script live seed base
  tmp="$(mktemp -d)"
  script="$REPO_DIR/scripts/seed_merge/pi.py"
  live="$tmp/live.json"
  seed="$tmp/seed.json"
  base="$tmp/base.json"

  cat > "$live" <<'EOF'
{
  "subagents": {
    "defaultModel": "openai-codex/gpt-5.6-luna",
    "agentOverrides": {
      "worker": {"model": "openai-codex/gpt-5.6-luna"},
      "reviewer": {"model": "openai-codex/gpt-5.6-luna"}
    }
  }
}
EOF
  cat > "$seed" <<'EOF'
{
  "subagents": {
    "defaultModel": "openai-codex/gpt-5.6-terra",
    "agentOverrides": {
      "worker": {"model": "openai-codex/gpt-5.6-luna"}
    }
  }
}
EOF

  python3 "$script" "$live" "$seed" "$seed" "$base" >/dev/null

  assert_equals "openai-codex/gpt-5.6-terra" "$(jq -r '.subagents.defaultModel' "$seed")"
  assert_equals "false" "$(jq '.subagents.agentOverrides | has("reviewer")' "$seed")"
  rm -rf "$tmp"
}
