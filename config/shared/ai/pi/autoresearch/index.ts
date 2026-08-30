import fs from "node:fs";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { commitExperiment, fingerprintWorktree, restoreExperiment, runGit } from "./git.ts";
import { isImprovement, parseMetrics } from "./metrics.ts";
import { readConfig, validatePilot } from "./safety.ts";

const TOOL_NAMES = ["autoresearch_run", "autoresearch_log"];
const AUTO_DIR = ".auto";
const LOG_FILE = "log.jsonl";

type RunResult = {
  commit: string;
  tree: string;
  metric: number | null;
  metrics: Record<string, number>;
  measureExit: number;
  checksExit: number | null;
  measureOutput: string;
  checksOutput: string;
};

function truncate(value: string, limit = 12000): string {
  return value.length <= limit ? value : `[truncated ${value.length - limit} bytes]\n${value.slice(-limit)}`;
}

function logPath(cwd: string): string {
  return path.join(cwd, AUTO_DIR, LOG_FILE);
}

function readEntries(cwd: string): Array<Record<string, unknown>> {
  const file = logPath(cwd);
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
}

async function requirePilot(ctx: ExtensionContext, requireFiles: boolean, requireClean: boolean): Promise<void> {
  const problem = await validatePilot(ctx.cwd, { requireFiles, requireClean });
  if (problem) throw new Error(problem);
}

function setToolsActive(pi: ExtensionAPI, active: boolean): void {
  const current = pi.getActiveTools().filter((name) => !TOOL_NAMES.includes(name));
  pi.setActiveTools(active ? [...new Set([...current, ...TOOL_NAMES])] : current);
}

export default function autoresearchExtension(pi: ExtensionAPI) {
  let active = false;
  let lastRun: RunResult | null = null;

  const setMode = (enabled: boolean) => {
    active = enabled;
    lastRun = null;
    setToolsActive(pi, enabled);
  };

  pi.on("session_start", () => setMode(false));
  pi.on("session_shutdown", () => setMode(false));

  pi.on("resources_discover", () => ({
    skillPaths: [path.join(import.meta.dirname, "skill")],
  }));

  pi.registerTool({
    name: "autoresearch_run",
    label: "Run autoresearch benchmark",
    description: "Run the bounded autoresearch benchmark and mandatory correctness checks",
    parameters: Type.Object({}),
    async execute(_id, _params, signal, _onUpdate, ctx) {
      if (!active) throw new Error("autoresearch mode is not active");
      await requirePilot(ctx, true, false);
      const config = readConfig(ctx.cwd);
      const entries = readEntries(ctx.cwd);
      if (entries.length >= config.maxIterations) throw new Error(`maximum experiments reached (${config.maxIterations})`);
      const hasBaseline = entries.some((entry) => entry.status === "baseline" || entry.status === "keep");
      if (!hasBaseline) await requirePilot(ctx, true, true);

      const commit = await runGit(ctx.cwd, ["rev-parse", "HEAD"], 5000);
      const measure = await pi.exec(path.join(ctx.cwd, AUTO_DIR, "measure.sh"), [], { cwd: ctx.cwd, signal, timeout: 600000 });
      let checksExit: number | null = null;
      let checksOutput = "";
      if (measure.code === 0) {
        const checks = await pi.exec(path.join(ctx.cwd, AUTO_DIR, "checks.sh"), [], { cwd: ctx.cwd, signal, timeout: 600000 });
        checksExit = checks.code;
        checksOutput = checks.stdout + checks.stderr;
      }
      const measureOutput = measure.stdout + measure.stderr;
      if (await runGit(ctx.cwd, ["rev-parse", "HEAD"], 5000) !== commit) {
        throw new Error("benchmark or checks changed Git HEAD");
      }
      const tree = await fingerprintWorktree(ctx.cwd);
      const metrics = parseMetrics(measureOutput);
      const metric = Object.hasOwn(metrics, config.metricName) ? metrics[config.metricName] : null;
      lastRun = {
        commit,
        tree,
        metric,
        metrics,
        measureExit: measure.code,
        checksExit,
        measureOutput: truncate(measureOutput),
        checksOutput: truncate(checksOutput),
      };
      return {
        content: [{
          type: "text",
          text: [
            `measure exit: ${measure.code}`,
            `checks exit: ${checksExit ?? "not run"}`,
            `${config.metricName}: ${metric ?? "missing"}`,
            `metrics: ${JSON.stringify(metrics)}`,
            measureOutput ? `measure output:\n${truncate(measureOutput)}` : "",
            checksOutput ? `checks output:\n${truncate(checksOutput)}` : "",
          ].filter(Boolean).join("\n"),
        }],
        details: lastRun,
      };
    },
  });

  pi.registerTool({
    name: "autoresearch_log",
    label: "Record autoresearch result",
    description: "Keep or discard the last bounded autoresearch experiment and commit its durable log",
    parameters: Type.Object({
      status: StringEnum(["baseline", "keep", "discard", "checks_failed", "crash"] as const),
      description: Type.String({ minLength: 1, maxLength: 240 }),
    }),
    async execute(_id, params, _signal, _onUpdate, ctx) {
      if (!active) throw new Error("autoresearch mode is not active");
      await requirePilot(ctx, true, false);
      if (!lastRun) throw new Error("run autoresearch_run before logging a result");
      const config = readConfig(ctx.cwd);
      const entries = readEntries(ctx.cwd);
      if (entries.length >= config.maxIterations) throw new Error(`maximum experiments reached (${config.maxIterations})`);
      if (params.status === "baseline" && entries.some((entry) => entry.status === "baseline" || entry.status === "keep")) {
        throw new Error("a valid baseline already exists");
      }
      if ((params.status === "baseline" || params.status === "keep") && (lastRun.measureExit !== 0 || lastRun.checksExit !== 0 || lastRun.metric === null)) {
        throw new Error(`cannot ${params.status} without a passing benchmark, checks, and primary metric`);
      }
      if (params.status === "keep") {
        const accepted = entries
          .filter((entry) => entry.status === "baseline" || entry.status === "keep")
          .map((entry) => entry.metric)
          .filter((metric): metric is number => typeof metric === "number" && Number.isFinite(metric));
        if (accepted.length === 0) throw new Error("cannot keep before a valid baseline");
        const best = config.direction === "lower" ? Math.min(...accepted) : Math.max(...accepted);
        if (!isImprovement(lastRun.metric!, accepted, config.direction)) {
          throw new Error(`cannot keep ${lastRun.metric}; best accepted ${config.metricName} is ${best}`);
        }
      }
      if (await runGit(ctx.cwd, ["rev-parse", "HEAD"], 5000) !== lastRun.commit) {
        throw new Error("Git HEAD changed after measurement; run autoresearch_run again");
      }
      if (await fingerprintWorktree(ctx.cwd) !== lastRun.tree) {
        throw new Error("worktree changed after measurement; run autoresearch_run again");
      }

      if (params.status === "discard" || params.status === "checks_failed" || params.status === "crash") await restoreExperiment(ctx.cwd);

      const file = logPath(ctx.cwd);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const existed = fs.existsSync(file);
      const original = existed ? fs.readFileSync(file) : Buffer.alloc(0);
      const entry = {
        run: entries.length + 1,
        timestamp: new Date().toISOString(),
        status: params.status,
        description: params.description,
        sourceCommit: lastRun.commit,
        metric: lastRun.metric,
        metrics: lastRun.metrics,
        measureExit: lastRun.measureExit,
        checksExit: lastRun.checksExit,
      };
      fs.appendFileSync(file, `${JSON.stringify(entry)}\n`, { mode: 0o600 });

      try {
        await commitExperiment(ctx.cwd, params.status, params.description);
      } catch (error) {
        if (existed) fs.writeFileSync(file, original);
        else fs.rmSync(file, { force: true });
        throw error;
      }

      lastRun = null;
      const done = entry.run >= config.maxIterations;
      return {
        content: [{ type: "text", text: `${params.status} recorded as run ${entry.run}/${config.maxIterations}${done ? "; stop now" : ""}` }],
        details: { entry, done },
        terminate: done,
      };
    },
  });

  pi.registerCommand("autoresearch", {
    description: "Start or stop a bounded, isolated optimization loop",
    handler: async (args, ctx) => {
      const request = (args ?? "").trim();
      if (request === "off") {
        if (!ctx.isIdle()) ctx.abort();
        setMode(false);
        ctx.ui.notify("Autoresearch mode OFF", "info");
        return;
      }
      if (!request) {
        ctx.ui.notify("Usage: /autoresearch <measurable goal> or /autoresearch off", "info");
        return;
      }
      const problem = await validatePilot(ctx.cwd, { requireFiles: false, requireClean: true });
      if (problem) {
        ctx.ui.notify(`Autoresearch unavailable: ${problem}`, "error");
        return;
      }
      setMode(true);
      const rulesExist = fs.existsSync(path.join(ctx.cwd, AUTO_DIR, "prompt.md"));
      ctx.ui.notify("Autoresearch mode ON", "info");
      pi.sendUserMessage(
        rulesExist
          ? `Resume bounded autoresearch for: ${request}. Read .auto/prompt.md, run autoresearch_run, and stop at maxIterations.`
          : `/skill:pi-autoresearch ${request}`,
        { expandPromptTemplates: true },
      );
    },
  });
}
