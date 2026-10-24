// Offline native credential-store integration: synthetic credentials only.
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, stat, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { loadModels, loginProviders } from "../../scripts/pi_auth_login.mjs";

const packageDirectory = process.argv[2];
const home = await mkdtemp(join(tmpdir(), "pi-auth-store-"));
process.env.HOME = home;
process.env.PI_CODING_AGENT_DIR = home;
for (const key of ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "AI_GATEWAY_API_KEY"]) delete process.env[key];
globalThis.fetch = () => { throw new Error("Network disabled in auth fixture"); };
const signal = new AbortController().signal;
const interaction = { signal, prompt: async () => { throw new Error("Unexpected prompt"); }, notify() {} };
try {
  const authPath = join(home, "auth.json");
  await writeFile(authPath, JSON.stringify({ unrelated: { type: "api_key", key: "synthetic-existing" } }), { mode: 0o600 });
  const { AuthStorage } = await import(pathToFileURL(join(packageDirectory, "dist/core/auth-storage.js")));
  const otherWriter = AuthStorage.create(authPath);
  const models = await loadModels(packageDirectory);
  let logins = 0;
  const fakeOAuth = {
    login: async () => {
      logins++;
      await otherWriter.modify("other-writer", async () => ({ type: "api_key", key: "synthetic-concurrent" }), { signal });
      return { type: "oauth", access: "synthetic-access", refresh: "synthetic-refresh", expires: Date.now() + 60000 };
    },
  };
  models.registerNativeProvider({ id: "openai-codex", name: "Offline Codex fixture", auth: { oauth: fakeOAuth }, getModels: () => [] });
  await loginProviders(models, ["openai-codex"], interaction);
  await loginProviders(models, ["openai-codex"], interaction);
  assert.equal(logins, 1, "Ready credentials must not be overwritten");
  const saved = JSON.parse(await readFile(authPath, "utf8"));
  assert.equal(saved.unrelated.key, "synthetic-existing");
  assert.equal(saved["other-writer"].key, "synthetic-concurrent");
  assert.equal(saved["openai-codex"].type, "oauth");
  if (process.platform !== "win32") assert.equal((await stat(authPath)).mode & 0o777, 0o600);
  const before = await readFile(authPath, "utf8");
  models.registerNativeProvider({ id: "openrouter", name: "Offline OpenRouter fixture", getModels: () => [], auth: {
    apiKey: { check: async () => undefined, login: async () => { throw new Error("synthetic login refusal"); } },
  } });
  await assert.rejects(loginProviders(models, ["openrouter"], interaction));
  await assert.rejects(loginProviders(models, ["openrouter"], { ...interaction, signal: AbortSignal.abort() }));
  assert.equal(await readFile(authPath, "utf8"), before, "Failure and cancellation must preserve storage");
  await loginProviders(await loadModels(packageDirectory), ["openrouter"], { ...interaction, prompt: async (request) => {
    assert.equal(request.type, "secret");
    return "synthetic-openrouter";
  } });
  assert.equal(JSON.parse(await readFile(authPath, "utf8")).openrouter.type, "api_key");
  await writeFile(authPath, "{malformed", { mode: 0o600 });
  await assert.rejects(loginProviders(await loadModels(packageDirectory), ["openrouter"], interaction));
  assert.equal(await readFile(authPath, "utf8"), "{malformed", "Malformed storage must not be replaced");
  console.log("native terminal auth: PASS (ready skip, locked persistence, other-writer preservation, failure, cancellation, malformed storage, private mode)");
} finally {
  await rm(home, { recursive: true, force: true });
}
