import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);

async function git(cwd: string, args: string[], signal?: AbortSignal): Promise<string> {
  const result = await exec("git", ["--no-pager", ...args], {
    cwd, signal, timeout: 15_000, maxBuffer: 1024 * 1024, windowsHide: true,
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0" },
  });
  return result.stdout;
}

export type ReviewTarget = { cwd: string; base: string; head: string; diff: string };

export async function verifyReview(target: ReviewTarget, signal?: AbortSignal): Promise<void> {
  if ((await git(target.cwd, ["rev-parse", "HEAD"], signal)).trim() !== target.head) {
    throw new Error("Review requires the requested head to remain checked out at HEAD.");
  }
  if ((await git(target.cwd, ["status", "--porcelain=v1", "--untracked-files=all"], signal)).trim()) {
    throw new Error("Review requires a clean checkout, including staged, unstaged and untracked files.");
  }
}

// debt: committed Git diffs only; add JJ/dirty/snapshot targets when a real review needs them.
export async function prepareReview(cwd: string, base: string, head: string, signal?: AbortSignal): Promise<ReviewTarget> {
  // Full object IDs avoid ambiguous refs and option/revision-expression injection.
  if (![base, head].every((sha) => /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(sha))) {
    throw new Error("Review base and head must be full commit object IDs.");
  }
  const root = (await git(cwd, ["rev-parse", "--show-toplevel"], signal)).trim();
  if (existsSync(join(root, ".jj"))) throw new Error("JJ review targets are not supported yet.");
  for (const sha of [base, head]) {
    if ((await git(root, ["cat-file", "-t", sha], signal)).trim() !== "commit") {
      throw new Error(`Not a commit: ${sha}`);
    }
  }
  const target = { cwd: root, base, head, diff: "" };
  await verifyReview(target, signal);
  target.diff = await git(root, ["diff", "--no-ext-diff", "--no-textconv", "--no-color", base, head, "--"], signal);
  if (!target.diff.trim()) throw new Error("Review diff is empty; refusing to switch scope.");
  // debt: 200 KB diff ceiling; add bounded diff paging if real reviews exceed this limit.
  if (Buffer.byteLength(target.diff) > 200_000) throw new Error("Review diff exceeds the 200 KB limit.");
  return target;
}
