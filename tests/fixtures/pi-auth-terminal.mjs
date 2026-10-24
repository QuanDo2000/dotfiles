// Attended PTY smoke test; input is an explicitly synthetic fixture, never a real key.
import assert from "node:assert/strict";
import { terminalInteraction } from "../../scripts/pi_auth_login.mjs";
const interaction = terminalInteraction(AbortSignal.timeout(30000));
const value = await interaction.prompt({ type: "secret", message: "Enter the synthetic test input (not a real key):" });
assert.equal(value, "synthetic-hidden-input");
const promptAbort = new AbortController();
const timer = setTimeout(() => promptAbort.abort(), 50);
try {
  await assert.rejects(interaction.prompt({ type: "manual_code", message: "Testing callback cancellation; do not enter anything.", signal: promptAbort.signal }));
} finally {
  clearTimeout(timer);
}
assert.ok(!process.stdin.isRaw, "Terminal input mode must be restored");
console.log("terminal prompts: PASS (input matched, callback cancellation, input mode restored)");
