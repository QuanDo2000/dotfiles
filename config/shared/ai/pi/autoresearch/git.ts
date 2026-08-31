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

export interface CreatedGitWorktree {
  kind: "git";
  name: string;
  path: string;
}

function worktreeSlug(goal: string): string {
  return goal.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40).replace(/-$/g, "") || "experiment";
}

function pathEntryExists(value: string): boolean {
  try {
    fs.lstatSync(value);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
}

function canonical(value: string): string {
  const resolved = path.resolve(value);
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

export async function createAutoresearchWorktree(cwd: string, goal: string): Promise<CreatedGitWorktree> {
  const root = await runGit(cwd, ["rev-parse", "--show-toplevel"]);
  const common = await runGit(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  if (canonical(root) !== canonical(cwd) || canonical(root) !== canonical(path.dirname(common))) {
    throw new Error("automatic Git setup requires the primary checkout root");
  }
  if (await runGit(cwd, ["status", "--porcelain=v1", "--untracked-files=all"])) {
    throw new Error("automatic Git setup requires a clean primary checkout");
  }
  const sourceRevision = await runGit(cwd, ["rev-parse", "HEAD"], 5000);
  const slug = worktreeSlug(goal);
  for (let suffix = 1; suffix <= 99; suffix += 1) {
    const candidate = suffix === 1 ? slug : `${slug}-${suffix}`;
    const name = `autoresearch/${candidate}`;
    const destination = path.join(path.dirname(path.resolve(cwd)), `autoresearch-${candidate}`);
    const branchExists = (await runGit(cwd, ["branch", "--list", name])) !== "";
    if (pathEntryExists(destination) || branchExists) continue;
    await runGit(cwd, ["worktree", "add", "-b", name, destination, sourceRevision]);
    return { kind: "git", name, path: destination };
  }
  throw new Error("could not allocate a unique autoresearch Git worktree name");
}

export async function removeAutoresearchWorktree(repositoryCwd: string, worktreePath: string): Promise<void> {
  const resolved = path.resolve(worktreePath);
  if (!fs.existsSync(path.join(resolved, ".git")) || !fs.lstatSync(path.join(resolved, ".git")).isFile()) {
    throw new Error("refusing to remove a path that is not a linked Git worktree");
  }
  const root = await runGit(resolved, ["rev-parse", "--show-toplevel"]);
  const repositoryCommon = await runGit(repositoryCwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const worktreeCommon = await runGit(resolved, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  if (canonical(root) !== canonical(resolved) || canonical(repositoryCommon) !== canonical(worktreeCommon)) {
    throw new Error("refusing to remove a worktree from a different Git repository");
  }
  if (await runGit(resolved, ["status", "--porcelain=v1", "--untracked-files=all"])) {
    throw new Error("refusing to remove a dirty Git worktree");
  }
  const branch = await runGit(resolved, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
  if (!branch.startsWith("autoresearch/")) throw new Error("refusing to remove a non-autoresearch Git worktree");
  await runGit(repositoryCwd, ["worktree", "remove", resolved]);
}

export async function rollbackAutoresearchWorktree(repositoryCwd: string, worktree: CreatedGitWorktree): Promise<void> {
  await removeAutoresearchWorktree(repositoryCwd, worktree.path);
  await runGit(repositoryCwd, ["branch", "-D", worktree.name]);
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
