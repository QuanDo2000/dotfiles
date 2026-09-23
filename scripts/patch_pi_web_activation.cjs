// pi-web-access 0.31.0 (MIT, Nico Bailon): use Pi's virtual-module-safe VERSION.
// debt: exact bundled-source patch; remove with the -web-version1 release suffix
// when a pinned upstream release uses the host VERSION export for detection.
const { readFileSync, writeFileSync } = require('node:fs');

const replacements = [
  ['import { buildSessionContext } from "@earendil-works/pi-coding-agent";',
    'import { buildSessionContext, VERSION as piWebAccessVersion } from "@earendil-works/pi-coding-agent";'],
  ['    const packagePath = join7(dirname2(fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent"))), "..", "package.json");\n    const [major, minor, patch] = JSON.parse(readFileSync42(packagePath, "utf8")).version.split(".").map(Number);',
    '    const [major, minor, patch] = piWebAccessVersion.split(".").map(Number);'],
];

try {
  const [path, mode] = process.argv.slice(2);
  if (!path || (mode !== undefined && mode !== '--check') || process.argv.length > 4) {
    throw new Error('Usage: patch_pi_web_activation.cjs <dist/index.js> [--check]');
  }
  const source = readFileSync(path, 'utf8');
  const count = text => source.split(text).length - 1;
  if (replacements.every(([oldText, newText]) => count(oldText) === 0 && count(newText) === 1)) process.exit(0);
  if (!replacements.every(([oldText, newText]) => count(oldText) === 1 && count(newText) === 0)) {
    throw new Error('Pi web activation patch source drift; review the pinned upstream implementation');
  }
  if (mode === '--check') throw new Error('Pi web activation patch has not been applied');
  // Validate all replacements before writing; callers patch only disposable staging trees.
  const patched = replacements.reduce((text, [oldText, newText]) => text.replace(oldText, newText), source);
  writeFileSync(path, patched);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
