import { readFile } from "node:fs/promises";
import type { Model, Usage } from "@earendil-works/pi-ai";
import {
  createAgentSession, createExtensionRuntime, SessionManager, SettingsManager,
  type ModelRuntime, type ResourceLoader,
} from "@earendil-works/pi-coding-agent";

export async function runReviewer(options: {
  cwd: string; prompt: string; model: Model; modelRuntime: ModelRuntime; signal?: AbortSignal;
}): Promise<{ text: string; usage: Usage }> {
  const controller = new AbortController();
  const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(300_000), ...(options.signal ? [options.signal] : [])]);
  signal.throwIfAborted();
  const rubric = await readFile(new URL("./rubric.md", import.meta.url), "utf8");
  // Explicit loader: no parent history, project instructions, extensions, skills or hooks.
  const resourceLoader: ResourceLoader = {
    getExtensions: () => ({ extensions: [], errors: [], runtime: createExtensionRuntime() }),
    getSkills: () => ({ skills: [], diagnostics: [] }),
    getPrompts: () => ({ prompts: [], diagnostics: [] }),
    getThemes: () => ({ themes: [], diagnostics: [] }),
    getAgentsFiles: () => ({ agentsFiles: [] }),
    getSystemPrompt: () => rubric,
    getSystemPromptSource: () => undefined,
    getAppendSystemPrompt: () => [],
    getAppendSystemPromptSources: () => [],
    extendResources: () => {},
    reload: async () => {},
  };
  const { session } = await createAgentSession({
    cwd: options.cwd, model: options.model, modelRuntime: options.modelRuntime,
    thinkingLevel: "medium", tools: ["read", "grep", "find", "ls"], resourceLoader,
    sessionManager: SessionManager.inMemory(options.cwd),
    settingsManager: SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } }),
  });
  const abort = () => { void session.abort(); };
  signal.addEventListener("abort", abort, { once: true });
  let turns = 0;
  const usage: Usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
  const unsubscribe = session.subscribe((event) => {
    if (event.type === "message_end" && event.message.role === "assistant") {
      const u = event.message.usage;
      for (const key of ["input", "output", "cacheRead", "cacheWrite", "totalTokens"] as const) usage[key] += u[key];
      for (const key of ["input", "output", "cacheRead", "cacheWrite", "total"] as const) usage.cost[key] += u.cost[key];
    }
    if (event.type === "turn_end" && ++turns >= 24 && event.message.stopReason === "toolUse") {
      controller.abort(new Error("Reviewer exceeded the 24-turn limit; review incomplete."));
    }
  });
  try {
    signal.throwIfAborted();
    await session.prompt(options.prompt, { expandPromptTemplates: false });
    signal.throwIfAborted();
    const last = session.messages.at(-1);
    if (!last || last.role !== "assistant" || last.stopReason !== "stop") {
      throw new Error(last?.role === "assistant" ? last.errorMessage || `Reviewer stopped with ${last.stopReason}; review incomplete.` : "Reviewer did not return findings.");
    }
    const text = last.content.filter(c => c.type === "text").map(c => c.text).join("\n").trim();
    if (!text) throw new Error("Reviewer returned empty findings.");
    return { text, usage };
  } finally {
    signal.removeEventListener("abort", abort);
    unsubscribe();
    session.dispose();
  }
}
