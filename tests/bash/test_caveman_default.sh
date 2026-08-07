#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_caveman_extension_injects_full_mode_by_default() {
  local skill status=0
  skill="$(mktemp)"
  cat > "$skill" <<'EOF'
---
name: caveman
description: Test skill
---
# Caveman

Keep all technical substance.
EOF

  CAVEMAN_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const caveman = require("./config/shared/ai/pi/caveman-default.js");
const handlers = {};

caveman({
  appendEntry() {},
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

const result = handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /^BASE\n\nCAVEMAN MODE ACTIVE — level: full/);
assert.match(result.systemPrompt, /Keep all technical substance\./);
assert.doesNotMatch(result.systemPrompt, /name: caveman/);
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_caveman_extension_honors_session_disable() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Caveman' 'Stay terse.' > "$skill"

  CAVEMAN_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const caveman = require("./config/shared/ai/pi/caveman-default.js");
const handlers = {};
const entries = [];

caveman({
  appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

handlers.input({ text: "stop caveman", source: "interactive" });
assert.equal(handlers.before_agent_start({ systemPrompt: "BASE" }), undefined);
assert.deepEqual(entries.at(-1), {
  type: "custom",
  customType: "caveman-mode",
  data: { mode: "off" },
});
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_caveman_extension_changes_level_with_command() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Caveman' 'Stay terse.' > "$skill"

  CAVEMAN_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const caveman = require("./config/shared/ai/pi/caveman-default.js");
const commands = {};
const handlers = {};
const entries = [];

caveman({
  appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
  on(name, handler) { handlers[name] = handler; },
  registerCommand(name, command) { commands[name] = command; },
});

commands.caveman.handler("ultra", { ui: { notify() {} } });
const result = handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /CAVEMAN MODE ACTIVE — level: ultra/);
assert.deepEqual(entries.at(-1).data, { mode: "ultra" });
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_caveman_extension_restores_session_mode() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Caveman' 'Stay terse.' > "$skill"

  CAVEMAN_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const caveman = require("./config/shared/ai/pi/caveman-default.js");
const handlers = {};

caveman({
  appendEntry() {},
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

handlers.session_start({}, {
  sessionManager: {
    getBranch() {
      return [{ type: "custom", customType: "caveman-mode", data: { mode: "wenyan-full" } }];
    },
  },
});
const result = handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /CAVEMAN MODE ACTIVE — level: wenyan-full/);
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_global_agents_relies_on_mode_injection() {
  local instructions
  instructions="$(<config/shared/ai/AGENTS.md)"

  assert_contains "$instructions" "In Pi, extensions inject their full instructions automatically. In other agents, load their installed skill instructions before the first response."
  assert_not_contains "$instructions" "Load their installed skill instructions before the first response;"
}

test_home_manager_installs_caveman_extension() {
  local config
  config="$(<config/home.nix)"

  assert_contains "$config" '".pi/agent/extensions/caveman-default.js" = forceSource ./shared/ai/pi/caveman-default.js;'
}
