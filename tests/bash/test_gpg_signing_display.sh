#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

test_gpg_signing_commands_suspend_pi_tui() {
  local status=0
  node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const extension = require("./config/shared/ai/pi/gpg-signing-display/core.js");
assert.equal(extension.needsInteractiveGpg("git -C /repo commit -m test"), true);
assert.equal(extension.needsInteractiveGpg("git tag v1"), true);
assert.equal(extension.needsInteractiveGpg("git tag --list"), false);
assert.equal(extension.needsInteractiveGpg("git merge --gpg-sign main"), true);
assert.equal(extension.needsInteractiveGpg("git merge -S0x1234 main"), true);
assert.equal(extension.needsInteractiveGpg("git log -S needle"), false);
assert.equal(extension.needsInteractiveGpg("git commit --no-gpg-sign -m test"), false);
assert.equal(extension.needsInteractiveGpg("echo git commit"), false);
const handlers = {};
let registered;
let baseCalls = 0;
const terminalEvents = [];

extension({
  on(name, handler) { handlers[name] = handler; },
  registerTool(tool) { registered = tool; },
}, {
  platform: "linux",
  createBashTool() {
    return {
      name: "bash",
      async execute() {
        baseCalls += 1;
        return { content: [{ type: "text", text: "base" }] };
      },
    };
  },
  spawnSync(_shell, _args, options) {
    assert.equal(options.stdio, "inherit");
    terminalEvents.push("spawn");
    return { status: 0 };
  },
});

handlers.session_start({}, { cwd: "/repo" });
const ctx = {
  mode: "tui",
  cwd: "/repo",
  ui: {
    async custom(factory) {
      let result;
      const tui = {
        stop() { terminalEvents.push("stop"); },
        start() { terminalEvents.push("start"); },
        requestRender(force) { assert.equal(force, true); },
      };
      factory(tui, {}, {}, (value) => { result = value; });
      return result;
    },
  },
};

(async () => {
  const result = await registered.execute("call", { command: "git add -A && git commit -m test" }, undefined, undefined, ctx);
  assert.equal(result.content[0].text, "Interactive signing command completed successfully.");
  assert.equal(baseCalls, 0);
  assert.deepEqual(terminalEvents, ["stop", "spawn", "start"]);
})();
NODE

  assert_equals 0 "$status"
}

test_non_signing_commands_keep_captured_bash() {
  local status=0
  node - <<'NODE' || status=$?
const assert = require("node:assert/strict");
const extension = require("./config/shared/ai/pi/gpg-signing-display/core.js");
const handlers = {};
let registered;
let baseCalls = 0;

extension({
  on(name, handler) { handlers[name] = handler; },
  registerTool(tool) { registered = tool; },
}, {
  platform: "linux",
  createBashTool() {
    return {
      name: "bash",
      async execute() {
        baseCalls += 1;
        return { content: [{ type: "text", text: "captured" }] };
      },
    };
  },
});

handlers.session_start({}, { cwd: "/repo" });
(async () => {
  const result = await registered.execute("call", { command: "git status --short" }, undefined, undefined, { mode: "tui" });
  assert.equal(result.content[0].text, "captured");
  assert.equal(baseCalls, 1);
})();
NODE

  assert_equals 0 "$status"
}

test_gpg_signing_display_extension_is_managed_on_unix_only() {
  local home_config windows_installer
  home_config="$(<config/home.nix)"
  windows_installer="$(<dotfile.ps1)"

  assert_contains "$home_config" '".pi/agent/extensions/gpg-signing-display" = forceSource ./shared/ai/pi/gpg-signing-display;'
  assert_not_contains "$windows_installer" 'gpg-signing-display'
}

test_gpg_signing_display_extension_loads_in_pi_session() {
  local output status=0
  output="$(pi --mode rpc --no-extensions -e config/shared/ai/pi/gpg-signing-display/index.ts </dev/null 2>&1)" || status=$?

  assert_equals 0 "$status"
  assert_not_contains "$output" 'Cannot find module'
}
