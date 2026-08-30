import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const AUTO_DIR = ".auto";

export interface AutoresearchConfig {
  maxIterations: number;
  metricName: string;
  direction: "lower" | "higher";
}

export interface PilotValidationOptions {
  requireFiles: boolean;
  requireClean: boolean;
  platform?: NodeJS.Platform;
}

function canonical(value: string): string {
  return path.resolve(value);
}

async function git(cwd: string, args: string[]): Promise<string> {
  const result = await execFileAsync("git", args, {
    cwd,
    encoding: "utf8",
    timeout: 5000,
    maxBuffer: 1024 * 1024,
  });
  return result.stdout.trim();
}

export function readConfig(cwd: string): AutoresearchConfig {
  const configPath = path.join(cwd, AUTO_DIR, "config.json");
  const parsed = JSON.parse(fs.readFileSync(configPath, "utf8")) as Record<string, unknown>;
  if ("workingDir" in parsed) throw new Error("workingDir overrides are disabled");
  if (!Number.isInteger(parsed.maxIterations) || Number(parsed.maxIterations) < 1 || Number(parsed.maxIterations) > 20) {
    throw new Error(".auto/config.json maxIterations must be an integer from 1 to 20");
  }
  if (typeof parsed.metricName !== "string" || !/^[A-Za-z][A-Za-z0-9_.-]*$/.test(parsed.metricName)) {
    throw new Error(".auto/config.json requires a valid metricName");
  }
  if (parsed.direction !== "lower" && parsed.direction !== "higher") {
    throw new Error('.auto/config.json direction must be "lower" or "higher"');
  }
  return parsed as unknown as AutoresearchConfig;
}

function validateScript(cwd: string, name: string): string | null {
  const script = path.join(cwd, AUTO_DIR, name);
  if (!fs.existsSync(script)) return `pi-autoresearch requires .auto/${name} as a regular executable file`;
  const stat = fs.lstatSync(script);
  if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o111) === 0) {
    return `pi-autoresearch requires .auto/${name} as a regular executable file`;
  }
  return null;
}

export async function validatePilot(cwd: string, options: PilotValidationOptions): Promise<string | null> {
  if ((options.platform ?? process.platform) !== "linux") return "pi-autoresearch is supported only on Linux";
  const workDir = canonical(cwd);
  const marker = path.join(workDir, ".git");
  if (!fs.existsSync(marker) || !fs.lstatSync(marker).isFile()) {
    return "pi-autoresearch requires a dedicated linked Git worktree (.git file)";
  }
  if (fs.existsSync(path.join(workDir, AUTO_DIR, "hooks"))) return "pi-autoresearch does not allow .auto/hooks";

  if (options.requireFiles) {
    try {
      readConfig(workDir);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
    for (const name of ["measure.sh", "checks.sh"]) {
      const problem = validateScript(workDir, name);
      if (problem) return problem;
    }
  }

  try {
    const root = await git(workDir, ["rev-parse", "--show-toplevel"]);
    const common = await git(workDir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
    const branch = await git(workDir, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
    if (canonical(root) !== workDir) return "pi-autoresearch requires Git root to match the Pi working directory";
    if (canonical(root) === canonical(path.dirname(common))) return "pi-autoresearch refuses the primary checkout";
    if (!branch.startsWith("autoresearch/")) return "pi-autoresearch requires an autoresearch/* branch";
    if (options.requireClean) {
      const status = await git(workDir, ["status", "--porcelain=v1", "--untracked-files=all"]);
      if (status) return "pi-autoresearch requires a clean worktree";
    }
  } catch (error) {
    return `pi-autoresearch Git validation failed: ${error instanceof Error ? error.message : String(error)}`;
  }
  return null;
}
