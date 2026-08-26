#!/usr/bin/env python3
"""Patch pi-hermes-memory so shutdown flush continues in a detached child."""

import os
import sys
import tempfile
from pathlib import Path


PATCHES = {
    "src/handlers/session-flush.ts": [
        (
            'import { execChildPrompt, resolveChildPiModel } from "./pi-child-process.js";',
            'import { execChildPrompt, execDetachedChildPrompt, resolveChildPiModel } from "./pi-child-process.js";',
            1,
        ),
        (
            "    timeoutMs = 30000,\n  ): Promise<void> {",
            "    timeoutMs = 30000,\n    detached = false,\n  ): Promise<void> {",
            1,
        ),
        (
            "    if (usesDirectTransport(config)) {",
            "    if (!detached && usesDirectTransport(config)) {",
            1,
        ),
        (
            """      await execChildPrompt(pi, flushMessage, config, {
        cwd: ctx.cwd,
        model: resolveChildPiModel(ctx.model),
        signal,
        timeoutMs,
      });""",
            """      const childOptions = {
        cwd: ctx.cwd,
        model: resolveChildPiModel(ctx.model),
        signal,
        timeoutMs,
      };
      if (detached) {
        await execDetachedChildPrompt(pi, flushMessage, config, childOptions);
      } else {
        await execChildPrompt(pi, flushMessage, config, childOptions);
      }""",
            1,
        ),
        (
            "    await flush(ctx, undefined, 10000);",
            "    await flush(ctx, undefined, 10000, true);",
            1,
        ),
    ],
    "src/handlers/pi-child-process.ts": [
        (
            'import { existsSync, readFileSync, readdirSync } from "node:fs";',
            'import { spawn } from "node:child_process";\nimport { existsSync, readFileSync, readdirSync } from "node:fs";',
            1,
        ),
        (
            """export async function execChildPrompt(
  pi: Pick<ExtensionAPI, "exec">,""",
            """export async function execDetachedChildPrompt(
  _pi: Pick<ExtensionAPI, "exec">,
  prompt: string,
  config: ChildLlmConfig,
  options: ExecChildPromptOptions,
  dependencies: ExecChildPromptDependencies = DEFAULT_EXEC_CHILD_PROMPT_DEPENDENCIES,
): Promise<void> {
  const temporaryPrompt = await writePromptToTemporaryFile(prompt);
  const promptReference = `@${temporaryPrompt.filePath}`;

  try {
    const childInvocation = resolveChildPiInvocation(
      buildChildPiPromptArgs(promptReference, config, process.argv.slice(2), options.model),
    );
    const invocation: ChildPiInvocation = {
      command: process.execPath,
      args: [
        CHILD_PROCESS_WATCHDOG_PATH,
        String(options.timeoutMs),
        "-",
        "--cleanup-dir",
        temporaryPrompt.dir,
        childInvocation.command,
        ...childInvocation.args,
      ],
    };

    await new Promise<void>((resolve, reject) => {
      let spawned = false;
      const child = spawn(invocation.command, invocation.args, {
        cwd: options.cwd,
        detached: true,
        stdio: "ignore",
        windowsHide: true,
      });
      child.once("error", (error) => {
        if (!spawned) reject(error);
      });
      child.once("spawn", () => {
        spawned = true;
        child.unref();
        resolve();
      });
    });
  } catch (error) {
    try { await dependencies.removeTemporaryDirectory(temporaryPrompt.dir); } catch {}
    throw error;
  }
}

export async function execChildPrompt(
  pi: Pick<ExtensionAPI, "exec">,""",
            1,
        ),
    ],
    "src/handlers/child-process-watchdog.mjs": [
        (
            """import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

const [timeoutValue, cancellationPath, command, ...args] = process.argv.slice(2);
const timeoutMs = Number(timeoutValue);

if (!cancellationPath || !command || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  process.stderr.write("pi-hermes-memory watchdog: invalid invocation\\n");
  process.exit(2);
}""",
            """import { spawn } from "node:child_process";
import { existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, resolve } from "node:path";

const [timeoutValue, cancellationPath, ...invocationArgs] = process.argv.slice(2);
const timeoutMs = Number(timeoutValue);
let cleanupDir;
if (invocationArgs[0] === "--cleanup-dir") {
  invocationArgs.shift();
  const candidate = resolve(invocationArgs.shift());
  if (dirname(candidate) === resolve(tmpdir()) && basename(candidate).startsWith("pi-hermes-prompt-")) {
    cleanupDir = candidate;
  }
}
const [command, ...args] = invocationArgs;

if (!cancellationPath || !command || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  process.stderr.write("pi-hermes-memory watchdog: invalid invocation\\n");
  process.exit(2);
}

function cleanupPromptDirectory() {
  if (!cleanupDir) return;
  try { rmSync(cleanupDir, { recursive: true, force: true }); } catch {}
}""",
            1,
        ),
        (
            """const child = spawn(command, args, {
  detached: process.platform !== "win32",
  stdio: ["ignore", "pipe", "pipe"],
});""",
            """const child = spawn(command, args, {
  detached: process.platform !== "win32",
  stdio: ["ignore", "pipe", "pipe"],
  windowsHide: true,
});""",
            1,
        ),
        (
            """  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);""",
            """  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);
  cleanupPromptDirectory();""",
            2,
        ),
    ],
}


def patch_source(source: str, replacements: list[tuple[str, str, int]]) -> str | None:
    old_present = [source.count(old) == count for old, _, count in replacements]
    new_present = [source.count(new) == count for _, new, count in replacements]
    if all(new_present):
        return None
    if not all(old_present) or any(new_present):
        raise ValueError("source drift")
    for old, new, _ in replacements:
        source = source.replace(old, new)
    return source


def atomic_write(path: Path, content: str) -> None:
    mode = path.stat().st_mode
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} PI_HERMES_MEMORY_DIR", file=sys.stderr)
        return 1

    root = Path(sys.argv[1])
    originals: dict[Path, str] = {}
    patched: dict[Path, str] = {}
    try:
        for relative, replacements in PATCHES.items():
            path = root / relative
            source = path.read_text(encoding="utf-8")
            originals[path] = source
            result = patch_source(source, replacements)
            if result is not None:
                patched[path] = result
    except (OSError, ValueError) as exc:
        print(f"Pi Hermes background flush patch source drift in {root}: {exc}", file=sys.stderr)
        return 1

    written: list[Path] = []
    try:
        for path, content in patched.items():
            atomic_write(path, content)
            written.append(path)
    except OSError as exc:
        for path in written:
            try:
                atomic_write(path, originals[path])
            except OSError:
                pass
        print(f"Failed to patch Pi Hermes background flush in {root}: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
