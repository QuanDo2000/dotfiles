import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isFastModeModel, rewriteFastModeProviderRequest } from "./core.ts";

const ENTRY_TYPE = "fast-mode-state";
const ENV_NAME = "PI_FAST_MODE";

interface FastModeState {
  enabled: boolean;
}

function savedState(ctx: ExtensionContext): boolean | undefined {
  let enabled: boolean | undefined;
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== "custom" || entry.customType !== ENTRY_TYPE) continue;
    const data = entry.data as Partial<FastModeState> | undefined;
    if (typeof data?.enabled === "boolean") enabled = data.enabled;
  }
  return enabled;
}

export default function registerFastMode(pi: ExtensionAPI): void {
  let enabled = false;

  const syncEnvironment = () => {
    if (enabled) process.env[ENV_NAME] = "1";
    else delete process.env[ENV_NAME];
  };

  const updateStatus = (ctx: ExtensionContext) => {
    const status = enabled
      ? isFastModeModel(ctx.model)
        ? "FAST"
        : "FAST (eligible models)"
      : undefined;
    ctx.ui.setStatus("fast-mode", status);
  };

  const describe = (ctx: ExtensionContext): string => {
    if (!enabled) return "Fast mode is off.";
    if (isFastModeModel(ctx.model)) return "Fast mode is on for the current model.";
    return "Fast mode is on, but the current model is unsupported.";
  };

  pi.on("session_start", (_event, ctx) => {
    const restored = savedState(ctx);
    enabled = restored ?? false;
    syncEnvironment();
    updateStatus(ctx);
  });

  pi.on("model_select", (_event, ctx) => updateStatus(ctx));

  pi.on("before_provider_request", (event, ctx) =>
    rewriteFastModeProviderRequest(event.payload, enabled, ctx.model),
  );

  pi.registerCommand("fast", {
    description: "Toggle priority tier for supported OpenAI-Codex models",
    handler: async (args, ctx) => {
      const action = args.trim().toLowerCase();
      if (action === "status") {
        ctx.ui.notify(describe(ctx), "info");
        return;
      }
      if (action && action !== "on" && action !== "off") {
        ctx.ui.notify("Usage: /fast [on|off|status]", "error");
        return;
      }

      enabled = action === "on" || (action === "" && !enabled);
      syncEnvironment();
      pi.appendEntry(ENTRY_TYPE, { enabled } satisfies FastModeState);
      updateStatus(ctx);
      const warning = enabled ? " Priority tier can increase quota usage or cost." : "";
      ctx.ui.notify(`${describe(ctx)}${warning}`, enabled && !isFastModeModel(ctx.model) ? "warning" : "info");
    },
  });
}
