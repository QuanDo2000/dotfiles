#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_caveman_extension_modes() {
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

function load() {
  const commands = {};
  const handlers = {};
  const entries = [];
  caveman({
    appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
    on(name, handler) { handlers[name] = handler; },
    registerCommand(name, command) { commands[name] = command; },
  });
  return { commands, handlers, entries };
}

let extension = load();
let result = extension.handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /^BASE\n\nCAVEMAN MODE ACTIVE — level: full/);
assert.match(result.systemPrompt, /Keep all technical substance\./);
assert.doesNotMatch(result.systemPrompt, /name: caveman/);

extension = load();
extension.handlers.input({ text: "stop caveman", source: "interactive" });
assert.equal(extension.handlers.before_agent_start({ systemPrompt: "BASE" }), undefined);
assert.deepEqual(extension.entries.at(-1), {
  type: "custom",
  customType: "caveman-mode",
  data: { mode: "off" },
});

extension = load();
extension.commands.caveman.handler("ultra", { ui: { notify() {} } });
result = extension.handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /CAVEMAN MODE ACTIVE — level: ultra/);
assert.deepEqual(extension.entries.at(-1).data, { mode: "ultra" });

extension = load();
extension.handlers.session_start({}, {
  sessionManager: {
    getBranch() {
      return [{ type: "custom", customType: "caveman-mode", data: { mode: "wenyan-full" } }];
    },
  },
});
result = extension.handlers.before_agent_start({ systemPrompt: "BASE" });
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
