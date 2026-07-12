const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";

function formatDuration(seconds) {
  const minutes = Math.max(0, Math.round(Number(seconds || 0) / 60));
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const remainder = minutes % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${remainder}m`;
  return `${remainder}m`;
}

function formatPlan(plan) {
  const known = { free: "Free", plus: "Plus", pro: "Pro", prolite: "Pro Lite", team: "Team" };
  return known[plan] || String(plan || "Unknown").replace(/(^|[_-])([a-z])/g, (_match, space, letter) => `${space ? " " : ""}${letter.toUpperCase()}`);
}

function formatWindow(label, window) {
  if (!window) return `${label}: unavailable`;
  return `${label}: ${window.used_percent ?? "?"}% used, resets in ${formatDuration(window.reset_after_seconds)}`;
}

function formatUsage(usage) {
  const limits = usage.rate_limit || {};
  const credits = usage.credits || {};
  const windows = [limits.primary_window, limits.secondary_window];
  return [
    `Plan: ${formatPlan(usage.plan_type)}`,
    formatWindow("5-hour limit", windows.find((window) => window?.limit_window_seconds === 18000)),
    formatWindow("Weekly limit", windows.find((window) => window?.limit_window_seconds === 604800)),
    `Reset tokens: ${usage.rate_limit_reset_credits?.available_count ?? "unavailable"}`,
    `Credits: $${credits.balance ?? "unavailable"}`,
  ].join("\n");
}

function authPath() {
  const directory = process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi", "agent");
  return path.join(directory, "auth.json");
}

function accountIdFromToken(token) {
  const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
  const accountId = payload?.["https://api.openai.com/auth"]?.chatgpt_account_id;
  if (!accountId) throw new Error("Codex OAuth token has no ChatGPT account ID");
  return accountId;
}

async function fetchUsage() {
  const auth = JSON.parse(await fs.readFile(authPath(), "utf8"));
  const token = auth?.["openai-codex"]?.access;
  if (!token) throw new Error("Codex login not found; run /login and select ChatGPT Plus/Pro");

  const response = await fetch(USAGE_URL, {
    headers: {
      Authorization: `Bearer ${token}`,
      "chatgpt-account-id": accountIdFromToken(token),
    },
  });
  if (!response.ok) {
    throw new Error(`ChatGPT usage request failed (${response.status}); run /login if credentials expired`);
  }
  return response.json();
}

function codexStatusExtension(pi) {
  pi.registerCommand("status", {
    description: "Show ChatGPT plan, Codex usage, and reset times",
    handler: async (_args, ctx) => {
      try {
        ctx.ui.notify(formatUsage(await fetchUsage()), "info");
      } catch (error) {
        ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
      }
    },
  });
}

module.exports = codexStatusExtension;
module.exports.formatDuration = formatDuration;
module.exports.formatUsage = formatUsage;
module.exports.fetchUsage = fetchUsage;
