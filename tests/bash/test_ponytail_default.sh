#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_ponytail_extension_injects_full_mode_by_default() {
  local skill status=0
  skill="$(mktemp)"
  cat > "$skill" <<'EOF'
---
name: ponytail
description: Test skill
---
# Ponytail

Use minimum code.
EOF

  PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const handlers = {};

ponytail({
  appendEntry() {},
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

const result = handlers.before_agent_start({ systemPrompt: "BASE" });
assert.match(result.systemPrompt, /^BASE\n\nPONYTAIL MODE ACTIVE — level: full/);
assert.match(result.systemPrompt, /Use minimum code\./);
assert.doesNotMatch(result.systemPrompt, /name: ponytail/);
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_ponytail_extension_honors_session_disable() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const handlers = {};
const entries = [];

ponytail({
  appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

handlers.input({ text: "stop ponytail", source: "interactive" });
assert.equal(handlers.before_agent_start({ systemPrompt: "BASE" }), undefined);
assert.deepEqual(entries.at(-1), {
  type: "custom",
  customType: "ponytail-mode",
  data: { mode: "off" },
});
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_ponytail_extension_changes_and_restores_level() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const commands = {};
const handlers = {};
const entries = [];

ponytail({
  appendEntry(customType, data) { entries.push({ type: "custom", customType, data }); },
  on(name, handler) { handlers[name] = handler; },
  registerCommand(name, command) { commands[name] = command; },
});

commands.ponytail.handler("ultra", { ui: { notify() {} } });
assert.match(handlers.before_agent_start({ systemPrompt: "BASE" }).systemPrompt, /PONYTAIL MODE ACTIVE — level: ultra/);
assert.deepEqual(entries.at(-1).data, { mode: "ultra" });

handlers.session_start({}, {
  sessionManager: {
    getBranch() {
      return [{ type: "custom", customType: "ponytail-mode", data: { mode: "lite" } }];
    },
  },
});
assert.match(handlers.before_agent_start({ systemPrompt: "BASE" }).systemPrompt, /PONYTAIL MODE ACTIVE — level: lite/);
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_ponytail_extension_honors_configured_default() {
  local config skill status=0
  config="$(mktemp -d)"
  skill="$(mktemp)"
  mkdir -p "$config/ponytail"
  printf '%s\n' '{"defaultMode":"lite"}' > "$config/ponytail/config.json"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  XDG_CONFIG_HOME="$config" PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const handlers = {};

ponytail({
  appendEntry() {},
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

assert.match(handlers.before_agent_start().systemPrompt, /^PONYTAIL MODE ACTIVE — level: lite/);
assert.doesNotMatch(handlers.before_agent_start().systemPrompt, /undefined/);
NODE

  assert_equals 0 "$status"
  rm -rf "$config" "$skill"
}

test_ponytail_extension_honors_environment_default() {
  local skill status=0
  skill="$(mktemp)"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  PONYTAIL_DEFAULT_MODE=off PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const handlers = {};

ponytail({
  appendEntry() {},
  on(name, handler) { handlers[name] = handler; },
  registerCommand() {},
});

assert.equal(handlers.before_agent_start({ systemPrompt: "BASE" }), undefined);
NODE

  assert_equals 0 "$status"
  rm -f "$skill"
}

test_ponytail_extension_writes_default_mode() {
  local config skill status=0
  config="$(mktemp -d)"
  skill="$(mktemp)"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  XDG_CONFIG_HOME="$config" PONYTAIL_DEFAULT_MODE=lite PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const commands = {};

ponytail({
  appendEntry() {},
  on() {},
  registerCommand(name, command) { commands[name] = command; },
});

const notices = [];
commands.ponytail.handler("default ultra", { ui: { notify(message, level) { notices.push({ message, level }); } } });
const config = JSON.parse(fs.readFileSync(path.join(process.env.XDG_CONFIG_HOME, "ponytail", "config.json")));
assert.equal(config.defaultMode, "ultra");
commands.ponytail.handler("status", { ui: { notify(message, level) { notices.push({ message, level }); } } });
assert.match(notices.at(-1).message, /default lite/);
NODE

  assert_equals 0 "$status"
  rm -rf "$config" "$skill"
}

test_ponytail_extension_reports_default_write_failure() {
  local config skill status=0
  config="$(mktemp)"
  skill="$(mktemp)"
  printf '%s\n' '# Ponytail' 'Use minimum code.' > "$skill"

  XDG_CONFIG_HOME="$config" PONYTAIL_SKILL_PATH="$skill" node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const ponytail = require("./config/shared/ai/pi/ponytail-default.js");
const commands = {};
const notices = [];

ponytail({
  appendEntry() {},
  on() {},
  registerCommand(name, command) { commands[name] = command; },
});

commands.ponytail.handler("default ultra", { ui: { notify(message, level) { notices.push({ message, level }); } } });
assert.equal(notices.at(-1).level, "error");
assert.match(notices.at(-1).message, /Failed to save default Ponytail mode/);
NODE

  assert_equals 0 "$status"
  rm -f "$config" "$skill"
}

test_home_manager_installs_ponytail_extension() {
  local config
  config="$(<config/home.nix)"

  assert_contains "$config" '".pi/agent/extensions/ponytail-default.js" = forceSource ./shared/ai/pi/ponytail-default.js;'
}
