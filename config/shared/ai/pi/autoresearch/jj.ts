import { execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export function isJjCommitId(value: string): boolean {
  return /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(value);
}

export interface JjState {
  commitId: string;
  changeId: string;
  parents: string[];
  description: string;
  author: { name: string; email: string; timestamp: string };
  empty: boolean;
  conflict: boolean;
}

export async function runJj(cwd: string, args: string[], timeout = 15000): Promise<string> {
  try {
    const result = await execFileAsync("jj", ["--no-pager", "--color=never", ...args], {
      cwd,
      encoding: "utf8",
      timeout,
      maxBuffer: 16 * 1024 * 1024,
    });
    return result.stdout.trim();
  } catch (error) {
    const failure = error as Error & { stdout?: string; stderr?: string; code?: number | string };
    const detail = `${failure.stdout ?? ""}${failure.stderr ?? ""}`.trim().slice(0, 500);
    throw new Error(`jj ${args[0]} failed${failure.code === undefined ? "" : ` (${failure.code})`}: ${detail || failure.message}`);
  }
}

export async function stateAt(cwd: string, revision = "@"): Promise<JjState> {
  const output = await runJj(cwd, [
    "log", "-r", revision, "--no-graph", "-T",
    'json(self) ++ "\\n" ++ if(empty, "true", "false") ++ "\\n" ++ if(conflict, "true", "false") ++ "\\n"',
  ]);
  const [serialized, empty, conflict] = output.split("\n");
  const parsed = JSON.parse(serialized ?? "") as {
    commit_id: string;
    change_id: string;
    parents: string[];
    description: string;
    author: { name: string; email: string; timestamp: string };
  };
  if (!isJjCommitId(parsed.commit_id ?? "") || !/^[a-z]{32}$/.test(parsed.change_id ?? "")) {
    throw new Error("jj returned an invalid working-copy identity");
  }
  return {
    commitId: parsed.commit_id,
    changeId: parsed.change_id,
    parents: parsed.parents,
    description: parsed.description,
    author: parsed.author,
    empty: empty === "true",
    conflict: conflict === "true",
  };
}

export interface CreatedJjWorkspace {
  kind: "jj";
  name: string;
  path: string;
}

function workspaceSlug(goal: string): string {
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

async function workspaceNames(cwd: string): Promise<Set<string>> {
  const output = await runJj(cwd, ["workspace", "list", "-T", 'name ++ "\\n"']);
  return new Set(output.split("\n").filter(Boolean));
}

export async function createAutoresearchWorkspace(cwd: string, goal: string): Promise<CreatedJjWorkspace> {
  const root = await runJj(cwd, ["root"]);
  const resolvedCwd = path.resolve(cwd);
  const normalize = (value: string) => process.platform === "win32" ? path.resolve(value).toLowerCase() : path.resolve(value);
  if (normalize(root) !== normalize(resolvedCwd)) throw new Error("JJ root must match the Pi working directory");
  const source = await stateAt(resolvedCwd);
  if (source.conflict) throw new Error("cannot create an autoresearch workspace from a conflicted working-copy commit");
  if (!source.empty) throw new Error("automatic JJ setup requires an empty working-copy commit");

  const slug = workspaceSlug(goal);
  const names = await workspaceNames(resolvedCwd);
  for (let suffix = 1; suffix <= 99; suffix += 1) {
    const candidate = suffix === 1 ? slug : `${slug}-${suffix}`;
    const name = `autoresearch-${candidate}`;
    const destination = path.join(path.dirname(resolvedCwd), name);
    if (pathEntryExists(destination) || names.has(name)) continue;
    await runJj(resolvedCwd, ["workspace", "add", "--name", name, "-r", source.commitId, destination]);
    return { kind: "jj", name, path: destination };
  }
  throw new Error("could not allocate a unique autoresearch JJ workspace name");
}

export async function currentWorkspaceName(cwd: string): Promise<string> {
  const state = await stateAt(cwd);
  const workspaces = (await runJj(cwd, ["workspace", "list", "-T", 'json(self) ++ "\\n"']))
    .split("\n").filter(Boolean).map((line) => JSON.parse(line) as { name: string; target: { commit_id: string } });
  const current = workspaces.filter((workspace) => workspace.target.commit_id === state.commitId);
  if (current.length !== 1) throw new Error("could not identify the current JJ workspace");
  return current[0].name;
}

export async function removeAutoresearchWorkspace(repositoryCwd: string, workspace: CreatedJjWorkspace): Promise<void> {
  const resolved = path.resolve(workspace.path);
  const marker = path.join(resolved, ".jj");
  if (!fs.existsSync(marker) || !fs.lstatSync(marker).isDirectory() || fs.lstatSync(marker).isSymbolicLink()) {
    throw new Error("refusing to remove a path that is not a JJ workspace");
  }
  const root = await runJj(resolved, ["root"]);
  const state = await stateAt(resolved);
  if ((process.platform === "win32" ? root.toLowerCase() : root) !== (process.platform === "win32" ? resolved.toLowerCase() : resolved)) {
    throw new Error("refusing to remove a nested JJ path");
  }
  if (state.conflict || !state.empty) throw new Error("refusing to remove a nonempty or conflicted JJ workspace");
  const names = await workspaceNames(repositoryCwd);
  if (!workspace.name.startsWith("autoresearch-") || !names.has(workspace.name)) {
    throw new Error("refusing to remove an unregistered JJ autoresearch workspace");
  }
  if (await currentWorkspaceName(resolved) !== workspace.name) throw new Error("JJ workspace identity changed");
  await runJj(repositoryCwd, ["workspace", "forget", workspace.name]);
  fs.rmSync(resolved, { recursive: true });
}

export async function revisionIdentity(cwd: string): Promise<string> {
  const state = await stateAt(cwd);
  return JSON.stringify({
    changeId: state.changeId,
    parents: state.parents,
    description: state.description,
    author: state.author,
  });
}

export async function fingerprintWorktree(cwd: string): Promise<string> {
  return (await stateAt(cwd)).commitId;
}

export async function restoreExperiment(cwd: string): Promise<void> {
  await runJj(cwd, ["restore", "--from", "@-", "all() ~ root:.auto"]);
}

export async function commitExperiment(cwd: string, status: string, description: string): Promise<string> {
  const subject = description.replace(/\s+/g, " ").trim().slice(0, 200);
  await runJj(cwd, ["commit", "-m", `autoresearch: ${status} ${subject}`]);
  return (await stateAt(cwd, "@-")).commitId;
}
