// Offline bundled-CLI startup check against the actual installed extension.
// Usage: node tests/ai/pi-web-activation-smoke.mjs <pi executable> <dist/index.js>
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const [pi, extension] = process.argv.slice(2);
assert.ok(pi && extension, 'Pass the Pi executable and extension dist/index.js');
const root = mkdtempSync(join(tmpdir(), 'pi-web-activation-'));
try {
  const entry = join(root, 'probe.ts');
  writeFileSync(entry, `
    import initialize from ${JSON.stringify(pathToFileURL(resolve(extension)).href)};
    export default function(pi) {
      let registered = false;
      initialize(new Proxy(pi, { get(target, key) {
        if (key === 'registerTool') return tool => {
          registered ||= tool.name === 'web_enable';
          target.registerTool(tool);
        };
        return target[key];
      }}));
      if (!registered) throw new Error('Supported host did not register web_enable');
      console.log('PI_WEB_ACTIVATION_OK');
    }
  `);
  const result = spawnSync(pi, ['--extension', entry, '--list-models', 'nonexistent-test-model'], {
    cwd: root, encoding: 'utf8', timeout: 30_000,
    env: { ...process.env, HOME: root, USERPROFILE: root, XDG_CONFIG_HOME: root, PI_CODING_AGENT_DIR: root },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /PI_WEB_ACTIVATION_OK/, result.stderr);
  assert.doesNotMatch(result.stderr, /Dynamic tool activation requires/);
  console.log('Bundled Pi registered web_enable without the compatibility warning');
} finally {
  rmSync(root, { recursive: true, force: true });
}
