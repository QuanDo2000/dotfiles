import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { isSupportedPlatform, scriptFileName, type SupportedPlatform } from "./runtime.ts";

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

function canonical(value: string, platform: SupportedPlatform): string {
  const resolved = path.resolve(value);
  return platform === "win32" ? resolved.toLowerCase() : resolved;
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
  const stat = fs.lstatSync(configPath);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(".auto/config.json must be a regular file");
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

function validateScript(cwd: string, name: "measure" | "checks", platform: SupportedPlatform): string | null {
  const fileName = scriptFileName(name, platform);
  const script = path.join(cwd, AUTO_DIR, fileName);
  const requirement = platform === "win32" ? "a regular file" : "a regular executable file";
  if (!fs.existsSync(script)) return `pi-autoresearch requires .auto/${fileName} as ${requirement}`;
  const stat = fs.lstatSync(script);
  if (!stat.isFile() || stat.isSymbolicLink() || (platform !== "win32" && (stat.mode & 0o111) === 0)) {
    return `pi-autoresearch requires .auto/${fileName} as ${requirement}`;
  }
  return null;
}

export async function validatePilot(cwd: string, options: PilotValidationOptions): Promise<string | null> {
  const platform = options.platform ?? process.platform;
  if (!isSupportedPlatform(platform)) return "pi-autoresearch is supported only on Linux, macOS, and Windows";
  const workDir = path.resolve(cwd);
  const marker = path.join(workDir, ".git");
  if (!fs.existsSync(marker) || !fs.lstatSync(marker).isFile()) {
    return "pi-autoresearch requires a dedicated linked Git worktree (.git file)";
  }
  const autoDir = path.join(workDir, AUTO_DIR);
  if (fs.existsSync(autoDir)) {
    const stat = fs.lstatSync(autoDir);
    if (!stat.isDirectory() || stat.isSymbolicLink()) return "pi-autoresearch requires .auto as a regular directory";
  } else if (options.requireFiles) {
    return "pi-autoresearch requires .auto as a regular directory";
  }
  if (fs.existsSync(path.join(autoDir, "hooks"))) return "pi-autoresearch does not allow .auto/hooks";

  if (options.requireFiles) {
    try {
      readConfig(workDir);
    } catch (error) {
      return error instanceof Error ? error.message : String(error);
    }
    for (const name of ["measure", "checks"] as const) {
      const problem = validateScript(workDir, name, platform);
      if (problem) return problem;
    }
  }

  try {
    const root = await git(workDir, ["rev-parse", "--show-toplevel"]);
    const common = await git(workDir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
    const branch = await git(workDir, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
    if (canonical(root, platform) !== canonical(workDir, platform)) return "pi-autoresearch requires Git root to match the Pi working directory";
    if (canonical(root, platform) === canonical(path.dirname(common), platform)) return "pi-autoresearch refuses the primary checkout";
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
