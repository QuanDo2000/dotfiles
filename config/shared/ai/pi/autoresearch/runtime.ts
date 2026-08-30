import path from "node:path";

export type SupportedPlatform = "linux" | "darwin" | "win32";

export function isSupportedPlatform(platform: NodeJS.Platform): platform is SupportedPlatform {
  return platform === "linux" || platform === "darwin" || platform === "win32";
}

export function scriptFileName(name: "measure" | "checks", platform: SupportedPlatform): string {
  return `${name}${platform === "win32" ? ".ps1" : ".sh"}`;
}

export function scriptCommand(
  cwd: string,
  name: "measure" | "checks",
  platform: SupportedPlatform,
  env: NodeJS.ProcessEnv,
): { command: string; args: string[] } {
  const script = path.join(cwd, ".auto", scriptFileName(name, platform));
  if (platform !== "win32") return { command: script, args: [] };

  const systemRoot = env.SystemRoot ?? env.SYSTEMROOT;
  if (!systemRoot || !/^[A-Za-z]:[\\/]/.test(systemRoot)) throw new Error("Windows SystemRoot is unavailable or invalid");
  const powershell = path.win32.join(systemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  return {
    command: powershell,
    args: ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script],
  };
}
