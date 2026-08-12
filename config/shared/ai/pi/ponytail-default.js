const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const MODES = new Set(["off", "lite", "full", "ultra"]);
const FALLBACK = "Use the smallest solution that works. Prefer deletion, standard library, and native platform features.";

function normalizeMode(value) {
  const mode = String(value || "").trim().toLowerCase();
  return MODES.has(mode) ? mode : undefined;
}

function configPath() {
  const root = process.env.XDG_CONFIG_HOME
    || (process.platform === "win32"
      ? process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming")
      : path.join(os.homedir(), ".config"));
  return path.join(root, "ponytail", "config.json");
}

function getDefaultMode() {
  const envMode = normalizeMode(process.env.PONYTAIL_DEFAULT_MODE);
  if (envMode) return envMode;
  try {
    const config = JSON.parse(fs.readFileSync(configPath(), "utf8").replace(/^\uFEFF/, ""));
    return normalizeMode(config.defaultMode) || "full";
  } catch {
    return "full";
  }
}

function writeDefaultMode(mode) {
  const file = configPath();
  let config = {};
  try {
    config = JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
    if (!config || typeof config !== "object" || Array.isArray(config)) config = {};
  } catch {}
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ ...config, defaultMode: mode }, null, 2), "utf8");
}

function loadInstructions() {
  const skillPath = process.env.PONYTAIL_SKILL_PATH
    || path.join(os.homedir(), ".agents", "skills", "ponytail", "SKILL.md");
  try {
    return fs.readFileSync(skillPath, "utf8").replace(/^---[\s\S]*?---\s*/, "").trim();
  } catch {
    return FALLBACK;
  }
}

function restoredMode(entries, fallback = "full") {
  for (let index = entries.length - 1; index >= 0; index -= 1) {
    const entry = entries[index];
    if (entry?.type === "custom" && entry.customType === "ponytail-mode") {
      return normalizeMode(entry.data?.mode) || "full";
    }
  }
  return normalizeMode(fallback) || "full";
}

function ponytailDefaultExtension(pi) {
  const instructions = loadInstructions();
  let configuredDefault = getDefaultMode();
  let mode = configuredDefault;

  const setMode = (next, ctx) => {
    mode = next;
    pi.appendEntry("ponytail-mode", { mode });
    ctx?.ui?.notify?.(`Ponytail mode set to ${mode}.`, "info");
  };

  pi.on("session_start", (_event, ctx) => {
    configuredDefault = getDefaultMode();
    mode = restoredMode(ctx.sessionManager.getBranch(), configuredDefault);
  });

  pi.on("input", (event) => {
    if (event.source === "extension") return;
    const text = String(event.text || "").trim().toLowerCase().replace(/[.!?\s]+$/, "");
    if (text === "stop ponytail" || text === "normal mode") setMode("off");
  });

  pi.registerCommand("ponytail", {
    description: "Set or report Ponytail mode",
    handler: (args, ctx) => {
      const value = String(args || "").trim().toLowerCase();
      if (value === "status") {
        ctx.ui.notify(`Ponytail: current ${mode} • default ${configuredDefault}`, "info");
        return;
      }
      if (value.startsWith("default ")) {
        const next = normalizeMode(value.slice(8));
        if (next) {
          try {
            writeDefaultMode(next);
            configuredDefault = getDefaultMode();
            const message = configuredDefault === next
              ? `Default Ponytail mode set to ${next}.`
              : `Saved default ${next}, but environment keeps default at ${configuredDefault}.`;
            ctx.ui.notify(message, "info");
          } catch (error) {
            ctx.ui.notify(`Failed to save default Ponytail mode: ${error.message}`, "error");
          }
          return;
        }
      }
      const next = normalizeMode(value || (configuredDefault === "off" ? "full" : configuredDefault));
      if (!next) {
        ctx.ui.notify("Use: /ponytail [off|lite|full|ultra|default <mode>]", "warning");
        return;
      }
      setMode(next, ctx);
    },
  });

  pi.on("before_agent_start", (event) => {
    if (mode === "off") return;
    const base = event?.systemPrompt ? `${event.systemPrompt}\n\n` : "";
    return {
      systemPrompt: `${base}PONYTAIL MODE ACTIVE — level: ${mode}\n\n${instructions}`,
    };
  });
}

module.exports = ponytailDefaultExtension;
module.exports.loadInstructions = loadInstructions;
module.exports.normalizeMode = normalizeMode;
module.exports.restoredMode = restoredMode;
