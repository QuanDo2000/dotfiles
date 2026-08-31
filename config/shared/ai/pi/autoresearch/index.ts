import fs from "node:fs";
import path from "node:path";
import { SessionManager, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { createAutoresearchWorktree, removeAutoresearchWorktree, rollbackAutoresearchWorktree, type CreatedGitWorktree } from "./git.ts";
import { createAutoresearchWorkspace, currentWorkspaceName, removeAutoresearchWorkspace, type CreatedJjWorkspace } from "./jj.ts";
import { formatCompletionSummary, isImprovement, parseMetrics } from "./metrics.ts";
import { commitExperiment, currentRevision, fingerprintWorktree, restoreExperiment, revisionIdentity, vcsKind } from "./vcs.ts";
import { isSupportedPlatform, scriptCommand } from "./runtime.ts";
import { readConfig, validatePilot } from "./safety.ts";

const TOOL_NAMES = ["autoresearch_run", "autoresearch_log"];
const AUTO_DIR = ".auto";
const LOG_FILE = "log.jsonl";

type CreatedWorkspace = CreatedGitWorktree | CreatedJjWorkspace;

type RunResult = {
  revision: string;
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
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(".auto/log.jsonl must be a regular file");
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
}

async function requirePilot(ctx: ExtensionContext, requireFiles: boolean, requireClean: boolean): Promise<void> {
  const problem = await validatePilot(ctx.cwd, { requireFiles, requireClean });
  if (problem) throw new Error(problem);
}

async function statusText(cwd: string, pending: boolean): Promise<string> {
  const problem = await validatePilot(cwd, { requireFiles: false, requireClean: false });
  if (problem) throw new Error(problem);
  const entries = readEntries(cwd);
  const lines = [
    `VCS: ${vcsKind(cwd)}`,
    `workspace: ${path.resolve(cwd)}`,
    `revision: ${(await currentRevision(cwd)).slice(0, 12)}`,
  ];
  const configFile = path.join(cwd, AUTO_DIR, "config.json");
  if (!fs.existsSync(configFile)) return [...lines, "iterations: 0 (not initialized)", `pending run: ${pending ? "yes" : "no"}`].join("\n");
  const config = readConfig(cwd);
  const accepted = entries
    .filter((entry) => entry.status === "baseline" || entry.status === "keep")
    .map((entry) => entry.metric)
    .filter((metric): metric is number => typeof metric === "number" && Number.isFinite(metric));
  const best = accepted.length === 0 ? "missing" : config.direction === "lower" ? Math.min(...accepted) : Math.max(...accepted);
  return [
    ...lines,
    `iterations: ${entries.length}/${config.maxIterations}`,
    `remaining: ${Math.max(0, config.maxIterations - entries.length)}`,
    `best ${config.metricName}: ${best}`,
    `last status: ${String(entries.at(-1)?.status ?? "none")}`,
    `pending run: ${pending ? "yes" : "no"}`,
  ].join("\n");
}

function persistEmptySession(session: Pick<SessionManager, "getSessionFile" | "getHeader">): string {
  const sessionFile = session.getSessionFile();
  if (!sessionFile) throw new Error("autoresearch workspace switching requires a persisted Pi session");
  if (!fs.existsSync(sessionFile)) {
    const header = session.getHeader();
    if (!header) throw new Error("could not create a Pi session header");
    fs.writeFileSync(sessionFile, `${JSON.stringify(header)}\n`, { flag: "wx", mode: 0o600 });
  }
  return sessionFile;
}

async function removeCreatedWorkspace(repositoryCwd: string, workspace: CreatedWorkspace): Promise<void> {
  if (workspace.kind === "jj") await removeAutoresearchWorkspace(repositoryCwd, workspace);
  else await removeAutoresearchWorktree(repositoryCwd, workspace.path);
}

async function rollbackCreatedWorkspace(repositoryCwd: string, workspace: CreatedWorkspace): Promise<void> {
  if (workspace.kind === "jj") await removeAutoresearchWorkspace(repositoryCwd, workspace);
  else await rollbackAutoresearchWorktree(repositoryCwd, workspace);
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

      const revision = await revisionIdentity(ctx.cwd);
      if (!isSupportedPlatform(process.platform)) throw new Error("unsupported autoresearch platform");
      const measureScript = scriptCommand(ctx.cwd, "measure", process.platform, process.env);
      const measure = await pi.exec(measureScript.command, measureScript.args, { cwd: ctx.cwd, signal, timeout: 600000 });
      let checksExit: number | null = null;
      let checksOutput = "";
      if (measure.code === 0) {
        const checksScript = scriptCommand(ctx.cwd, "checks", process.platform, process.env);
        const checks = await pi.exec(checksScript.command, checksScript.args, { cwd: ctx.cwd, signal, timeout: 600000 });
        checksExit = checks.code;
        checksOutput = checks.stdout + checks.stderr;
      }
      const measureOutput = measure.stdout + measure.stderr;
      if (await revisionIdentity(ctx.cwd) !== revision) {
        throw new Error("benchmark or checks changed the VCS revision");
      }
      const tree = await fingerprintWorktree(ctx.cwd);
      const metrics = parseMetrics(measureOutput);
      const metric = Object.hasOwn(metrics, config.metricName) ? metrics[config.metricName] : null;
      lastRun = {
        revision,
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
      if (await revisionIdentity(ctx.cwd) !== lastRun.revision) {
        throw new Error("VCS revision changed after measurement; run autoresearch_run again");
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
        vcs: vcsKind(ctx.cwd),
        sourceRevision: lastRun.revision,
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
      const completion = done
        ? formatCompletionSummary([...entries, entry], config.metricName, config.direction, ctx.cwd)
        : "";
      return {
        content: [{
          type: "text",
          text: [`${params.status} recorded as run ${entry.run}/${config.maxIterations}`, completion].filter(Boolean).join("\n\n"),
        }],
        details: { entry, done },
        terminate: done,
      };
    },
  });

  pi.registerCommand("autoresearch", {
    description: "Start, inspect, stop, or clean up a bounded optimization loop",
    handler: async (args, ctx) => {
      const request = (args ?? "").trim();
      if (request === "off") {
        if (!ctx.isIdle()) ctx.abort();
        setMode(false);
        ctx.ui.notify("Autoresearch mode OFF", "info");
        return;
      }
      if (request === "status") {
        try {
          ctx.ui.notify(await statusText(ctx.cwd, lastRun !== null), "info");
        } catch (error) {
          ctx.ui.notify(`Autoresearch status unavailable: ${error instanceof Error ? error.message : String(error)}`, "error");
        }
        return;
      }
      if (request === "cleanup") {
        const problem = await validatePilot(ctx.cwd, { requireFiles: false, requireClean: true });
        if (problem) {
          ctx.ui.notify(`Autoresearch cleanup unavailable: ${problem}`, "error");
          return;
        }
        const parentSession = ctx.sessionManager.getHeader()?.parentSession;
        if (!parentSession || !fs.existsSync(parentSession)) {
          ctx.ui.notify("Autoresearch cleanup requires the parent session created by automatic workspace setup", "error");
          return;
        }
        const targetCwd = ctx.cwd;
        const targetSession = ctx.sessionManager.getSessionFile();
        const kind = vcsKind(targetCwd);
        const workspace: CreatedWorkspace = kind === "jj"
          ? { kind, name: await currentWorkspaceName(targetCwd), path: targetCwd }
          : { kind, name: "", path: targetCwd };
        if (!await ctx.ui.confirm("Remove autoresearch workspace?", `Preserve committed history and remove ${targetCwd}?`)) return;
        setMode(false);
        const switched = await ctx.switchSession(parentSession, {
          withSession: async (replacementCtx) => {
            try {
              await removeCreatedWorkspace(replacementCtx.cwd, workspace);
              if (targetSession) fs.rmSync(targetSession, { force: true });
              replacementCtx.ui.notify(
                kind === "jj" ? `Removed JJ workspace ${workspace.name}` : `Removed Git worktree ${targetCwd}; branch preserved`,
                "info",
              );
            } catch (error) {
              replacementCtx.ui.notify(`Autoresearch cleanup failed: ${error instanceof Error ? error.message : String(error)}`, "error");
            }
          },
        });
        if (switched.cancelled) ctx.ui.notify("Autoresearch cleanup cancelled; workspace preserved", "info");
        return;
      }
      if (!request) {
        ctx.ui.notify("Usage: /autoresearch <goal>|off|status|cleanup", "info");
        return;
      }

      const problem = await validatePilot(ctx.cwd, { requireFiles: false, requireClean: true });
      const autoJj = problem?.includes("dedicated autoresearch-* workspace") && fs.existsSync(path.join(ctx.cwd, ".jj"));
      const gitMarker = path.join(ctx.cwd, ".git");
      const autoGit = problem?.includes("linked Git worktree") && fs.existsSync(gitMarker) && fs.lstatSync(gitMarker).isDirectory();
      if (autoJj || autoGit) {
        let workspace: CreatedWorkspace | null = null;
        let sessionFile: string | null = null;
        let entered = false;
        try {
          const parentSession = persistEmptySession(ctx.sessionManager);
          workspace = autoJj
            ? await createAutoresearchWorkspace(ctx.cwd, request)
            : await createAutoresearchWorktree(ctx.cwd, request);
          const workspaceProblem = await validatePilot(workspace.path, { requireFiles: false, requireClean: true });
          if (workspaceProblem) throw new Error(workspaceProblem);
          const session = SessionManager.create(workspace.path, undefined, { parentSession });
          sessionFile = persistEmptySession(session);
          const switched = await ctx.switchSession(sessionFile, {
            withSession: async (replacementCtx) => {
              replacementCtx.ui.notify(`Created ${workspace!.kind === "jj" ? "JJ workspace" : "Git worktree"} ${workspace!.name} at ${workspace!.path}`, "info");
              try {
                await replacementCtx.sendUserMessage(`/autoresearch ${request}`, { expandPromptTemplates: true });
                entered = true;
              } catch (error) {
                entered = true;
                const activationError = error instanceof Error ? error.message : String(error);
                try {
                  const returned = await replacementCtx.switchSession(parentSession, {
                    withSession: async (parentCtx) => {
                      try {
                        await rollbackCreatedWorkspace(parentCtx.cwd, workspace!);
                        fs.rmSync(sessionFile!, { force: true });
                        parentCtx.ui.notify(`Autoresearch activation failed and workspace was rolled back: ${activationError}`, "error");
                      } catch (rollbackError) {
                        parentCtx.ui.notify(
                          `Autoresearch activation failed: ${activationError}; rollback failed for ${workspace!.path}: ${rollbackError instanceof Error ? rollbackError.message : String(rollbackError)}`,
                          "error",
                        );
                      }
                    },
                  });
                  if (returned.cancelled) replacementCtx.ui.notify(`Autoresearch activation failed; workspace remains at ${workspace!.path}`, "error");
                } catch (rollbackError) {
                  replacementCtx.ui.notify(
                    `Autoresearch activation failed: ${activationError}; workspace remains at ${workspace!.path}: ${rollbackError instanceof Error ? rollbackError.message : String(rollbackError)}`,
                    "error",
                  );
                }
              }
            },
          });
          if (switched.cancelled && workspace) {
            await rollbackCreatedWorkspace(ctx.cwd, workspace);
            if (sessionFile) fs.rmSync(sessionFile, { force: true });
            ctx.ui.notify("Session switch cancelled; created workspace rolled back", "info");
          }
        } catch (error) {
          let detail = error instanceof Error ? error.message : String(error);
          if (workspace && !entered) {
            try {
              await rollbackCreatedWorkspace(ctx.cwd, workspace);
              if (sessionFile) fs.rmSync(sessionFile, { force: true });
            } catch (rollbackError) {
              detail += `; rollback failed: ${rollbackError instanceof Error ? rollbackError.message : String(rollbackError)}`;
            }
          }
          if (!entered) ctx.ui.notify(`Autoresearch unavailable: ${detail}`, "error");
        }
        return;
      }
      if (problem) {
        ctx.ui.notify(`Autoresearch unavailable: ${problem}`, "error");
        return;
      }
      setMode(true);
      pi.setSessionName(`autoresearch: ${request}`);
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
