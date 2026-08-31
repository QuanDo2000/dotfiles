import fs from "node:fs";
import path from "node:path";
import {
  commitExperiment as commitGitExperiment,
  fingerprintWorktree as fingerprintGitWorktree,
  restoreExperiment as restoreGitExperiment,
  runGit,
} from "./git.ts";
import {
  commitExperiment as commitJjExperiment,
  fingerprintWorktree as fingerprintJjWorktree,
  restoreExperiment as restoreJjExperiment,
  revisionIdentity as jjRevisionIdentity,
  stateAt,
} from "./jj.ts";

export type VcsKind = "git" | "jj";

export function vcsKind(cwd: string): VcsKind {
  return fs.existsSync(path.join(cwd, ".jj")) ? "jj" : "git";
}

export async function revisionIdentity(cwd: string): Promise<string> {
  return vcsKind(cwd) === "jj" ? jjRevisionIdentity(cwd) : runGit(cwd, ["rev-parse", "HEAD"], 5000);
}

export async function currentRevision(cwd: string): Promise<string> {
  return vcsKind(cwd) === "jj" ? (await stateAt(cwd)).commitId : runGit(cwd, ["rev-parse", "HEAD"], 5000);
}

export async function fingerprintWorktree(cwd: string): Promise<string> {
  return vcsKind(cwd) === "jj" ? fingerprintJjWorktree(cwd) : fingerprintGitWorktree(cwd);
}

export async function restoreExperiment(cwd: string): Promise<void> {
  if (vcsKind(cwd) === "jj") await restoreJjExperiment(cwd);
  else await restoreGitExperiment(cwd);
}

export async function commitExperiment(cwd: string, status: string, description: string): Promise<string> {
  return vcsKind(cwd) === "jj"
    ? commitJjExperiment(cwd, status, description)
    : commitGitExperiment(cwd, status, description);
}
