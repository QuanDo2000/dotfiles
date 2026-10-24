// Terminal interaction only; OAuth and credential persistence remain owned by installed Pi.

import { join, resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";
import { pathToFileURL } from "node:url";

const methods = { "openai-codex": "oauth", openrouter: "api_key" };

export async function loadModels(packageDirectory) {
  const { ModelRuntime } = await import(pathToFileURL(join(packageDirectory, "dist/core/model-runtime.js")));
  return ModelRuntime.create({ modelsPath: null, allowModelNetwork: false, refreshOnCreate: false });
}

export async function loginProviders(models, providers, interaction) {
  if (!providers.length || providers.length > 2 || new Set(providers).size !== providers.length ||
      providers.some((id) => !Object.hasOwn(methods, id))) {
    throw new Error("Invalid provider selection");
  }
  for (const provider of providers) {
    // Recheck in case another application completed the login since the parent checked.
    if (await models.checkAuth(provider, { signal: interaction.signal })) continue;
    console.log(`\nSet up Pi ${provider} (${methods[provider]}). Ctrl+C cancels.`);
    await models.login(provider, methods[provider], interaction);
    console.log(`Pi ${provider}: credential saved.`);
  }
}

export function terminalInteraction(signal) {
  return {
    signal,
    async prompt(request) {
      console.log(`\n${request.message}`);
      if (request.type === "select") {
        request.options.forEach((option, index) => console.log(`  ${index + 1}. ${option.label}`));
      }
      // Hide all entered text, including API keys and pasted OAuth redirect codes.
      const muted = new Writable({ write(_chunk, _encoding, done) { done(); } });
      const rl = createInterface({ input: process.stdin, output: muted, terminal: true });
      const cancel = new AbortController();
      rl.once("SIGINT", () => cancel.abort());
      rl.once("close", () => cancel.abort());
      const signals = [signal, cancel.signal];
      if (request.signal) signals.push(request.signal);
      process.stdout.write(request.type === "select" ? "Choice (input hidden): " : "Input (hidden): ");
      try {
        const value = await rl.question("", { signal: AbortSignal.any(signals) });
        if (!value.trim() || value.length > 8192) throw new Error("Invalid input length");
        if (request.type !== "select") return value.trim();
        if (!/^[1-9][0-9]*$/.test(value.trim())) throw new Error("Invalid selection");
        const option = request.options[Number(value.trim()) - 1];
        if (!option) throw new Error("Invalid selection");
        return option.id;
      } finally {
        rl.close();
        muted.destroy();
        process.stdout.write("\n");
      }
    },
    notify(event) {
      if (event.type === "auth_url") {
        console.log(`\nOpen this link in your browser:\n${event.url}`);
      } else if (event.type === "device_code") {
        console.log(`\nOpen ${event.verificationUri}\nEnter device code: ${event.userCode}`);
      } else if (event.type === "info" || event.type === "progress") {
        console.log(event.message);
      }
    },
  };
}

async function main() {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error("Local terminal required");
  const [packageDirectory, ...providers] = process.argv.slice(2);
  if (!packageDirectory) throw new Error("Installed Pi directory required");
  const controller = new AbortController();
  const interrupt = () => controller.abort();
  process.once("SIGINT", interrupt);
  const timeout = setTimeout(interrupt, 14 * 60 * 1000);
  try {
    const models = await loadModels(resolve(packageDirectory));
    await loginProviders(models, providers, terminalInteraction(controller.signal));
  } finally {
    clearTimeout(timeout);
    process.removeListener("SIGINT", interrupt);
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(() => {
    // Native errors may contain authorization URLs or provider response details.
    console.error("Pi terminal login did not complete. Rerun pi-auth to check the current state.");
    process.exitCode = 1;
  });
}
