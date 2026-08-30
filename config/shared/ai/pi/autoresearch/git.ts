import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

async function executeGit(cwd: string, args: string[], timeout: number, env?: NodeJS.ProcessEnv): Promise<string> {
  try {
    const result = await execFileAsync("git", args, {
      cwd,
      encoding: "utf8",
      env: env ?? process.env,
      timeout,
      maxBuffer: 16 * 1024 * 1024,
    });
    return result.stdout.trim();
  } catch (error) {
    const failure = error as Error & { stdout?: string; stderr?: string; code?: number | string };
    const detail = `${failure.stdout ?? ""}${failure.stderr ?? ""}`.trim().slice(0, 500);
    throw new Error(`git ${args[0]} failed${failure.code === undefined ? "" : ` (${failure.code})`}: ${detail || failure.message}`);
  }
}

export async function runGit(cwd: string, args: string[], timeout = 15000): Promise<string> {
  return executeGit(cwd, args, timeout);
}

export async function fingerprintWorktree(cwd: string): Promise<string> {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "pi-autoresearch-index-"));
  const index = path.join(temporary, "index");
  const env = { ...process.env, GIT_INDEX_FILE: index };
  try {
    await executeGit(cwd, ["read-tree", "HEAD"], 15000, env);
    await executeGit(cwd, ["add", "-A"], 15000, env);
    return await executeGit(cwd, ["write-tree"], 15000, env);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

export async function restoreExperiment(cwd: string): Promise<void> {
  await runGit(cwd, ["restore", "--source=HEAD", "--staged", "--worktree", "--", ".", ":(exclude).auto", ":(exclude).auto/**"]);
  await runGit(cwd, ["clean", "-fd", "-e", ".auto/", "--"]);
}

export async function commitExperiment(cwd: string, status: string, description: string): Promise<string> {
  try {
    const addArgs = status === "keep" ? ["add", "-A"] : ["add", "--", ".auto"];
    await runGit(cwd, addArgs);
    const subject = description.replace(/\s+/g, " ").trim().slice(0, 200);
    await runGit(cwd, ["commit", "-m", `autoresearch: ${status} ${subject}`]);
    return await runGit(cwd, ["rev-parse", "HEAD"], 5000);
  } catch (error) {
    try {
      await runGit(cwd, ["reset", "--mixed", "HEAD", "--"], 5000);
    } catch {
      // Preserve the original commit failure; the worktree remains isolated.
    }
    throw error;
  }
}
