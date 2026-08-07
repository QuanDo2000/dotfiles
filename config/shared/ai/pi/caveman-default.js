const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const MODES = new Set([
  "off",
  "lite",
  "full",
  "ultra",
  "wenyan-lite",
  "wenyan-full",
  "wenyan-ultra",
]);
const FALLBACK = "Respond terse like smart caveman. Keep all technical substance; drop filler, pleasantries, and hedging.";

function normalizeMode(value) {
  const mode = String(value || "full").trim().toLowerCase();
  if (mode === "wenyan") return "wenyan-full";
  return MODES.has(mode) ? mode : undefined;
}

function loadInstructions() {
  const skillPath = process.env.CAVEMAN_SKILL_PATH
    || path.join(os.homedir(), ".agents", "skills", "caveman", "SKILL.md");
  try {
    return fs.readFileSync(skillPath, "utf8").replace(/^---[\s\S]*?---\s*/, "").trim();
  } catch {
    return FALLBACK;
  }
}

function restoredMode(entries) {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry?.type === "custom" && entry.customType === "caveman-mode") {
      return normalizeMode(entry.data?.mode) || "full";
    }
  }
  return "full";
}

function cavemanDefaultExtension(pi) {
  const instructions = loadInstructions();
  let mode = "full";

  const setMode = (next, ctx) => {
    mode = next;
    pi.appendEntry("caveman-mode", { mode });
    ctx?.ui?.notify?.(`Caveman mode set to ${mode}.`, "info");
  };

  pi.on("session_start", (_event, ctx) => {
    mode = restoredMode(ctx.sessionManager.getBranch());
  });

  pi.on("input", (event) => {
    if (event.source === "extension") return;
    const text = String(event.text || "").trim().toLowerCase().replace(/[.!?\s]+$/, "");
    if (text === "stop caveman" || text === "normal mode") {
      setMode("off");
      return;
    }
    const match = text.match(/^\/skill:caveman(?:\s+(\S+))?$/);
    const next = match && normalizeMode(match[1]);
    if (next) setMode(next);
  });

  pi.registerCommand("caveman", {
    description: "Set or report Caveman mode",
    handler: (args, ctx) => {
      const value = String(args || "").trim().toLowerCase();
      if (value === "status") {
        ctx.ui.notify(`Caveman: ${mode}`, "info");
        return;
      }
      const next = normalizeMode(value);
      if (!next) {
        ctx.ui.notify("Use: /caveman [off|lite|full|ultra|wenyan-lite|wenyan-full|wenyan-ultra]", "warning");
        return;
      }
      setMode(next, ctx);
    },
  });

  pi.on("before_agent_start", (event) => {
    if (mode === "off") return;
    return {
      systemPrompt: `${event.systemPrompt}\n\nCAVEMAN MODE ACTIVE — level: ${mode}\n\n${instructions}`,
    };
  });
}

module.exports = cavemanDefaultExtension;
module.exports.loadInstructions = loadInstructions;
module.exports.normalizeMode = normalizeMode;
module.exports.restoredMode = restoredMode;
