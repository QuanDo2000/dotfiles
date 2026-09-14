// Offline provider: exercise a real agent tool call without running experiments.
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("autoresearch-test", {
    baseUrl: "http://unused.invalid",
    apiKey: "fixture-only",
    api: "openai-completions",
    models: [{
      id: "fixture", name: "Fixture", reasoning: false, input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 100000, maxTokens: 1000,
    }],
    streamSimple(model, context) {
      if (context.messages.some((message) => message.role === "toolResult")) {
        throw new Error("Unexpected model continuation after startup tool");
      }
      const stream = createAssistantMessageEventStream();
      stream.push({ type: "done", reason: "toolUse", message: {
        role: "assistant", api: model.api, provider: model.provider, model: model.id,
        content: [{ type: "toolCall", id: "start", name: "autoresearch_start", arguments: { goal: process.env.TEST_GOAL } }],
        usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
        stopReason: "toolUse", timestamp: Date.now(),
      } });
      stream.end();
      return stream;
    },
  });
  pi.registerCommand("test-probe", {
    handler: async (_args, ctx) => {
      ctx.ui.notify(JSON.stringify({
        probe: true, cwd: ctx.cwd, session: ctx.sessionManager.getSessionFile(),
        parent: ctx.sessionManager.getHeader()?.parentSession,
        active: pi.getActiveTools(),
      }), "info");
    },
  });
  pi.registerCommand("test-reload", { handler: async (_args, ctx) => { await ctx.reload(); } });
  pi.on("session_before_switch", (event) => {
    if (process.env.TEST_CANCEL === "1" && event.targetSessionFile?.includes("autoresearch-")) return { cancel: true };
  });
  pi.on("input", (event, ctx) => {
    if (event.text.startsWith("/skill:pi-autoresearch ") || event.text.startsWith("Resume bounded autoresearch")) {
      ctx.ui.notify(JSON.stringify({ kickoff: event.text, cwd: ctx.cwd }), "info");
      return { action: "handled" };
    }
  });
}
