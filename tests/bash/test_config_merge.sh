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
