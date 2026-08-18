#!/usr/bin/env python3
"""Patch Pi MCP startup to wait for eager tools only in subagents."""

import sys
from pathlib import Path

OLD = """    // Start all eager servers concurrently
    await Promise.allSettled(
      eagerServers.map(async ([name]) => {
        try {
          await manager.startServer(name, ctx.cwd);
        } catch (err) {
          const msg = err instanceof McpError ? err.userMessage : String(err);
          ctx.ui.notify(`pi-mcp: Failed to start ${name} — ${msg}`, "error");
        }
      }),
    );"""
LEGACY = """    // Start all eager servers concurrently without blocking session startup
    void Promise.allSettled(
      eagerServers.map(async ([name]) => {
        try {
          await manager.startServer(name, ctx.cwd);
        } catch (err) {
          const msg = err instanceof McpError ? err.userMessage : String(err);
          ctx.ui.notify(`pi-mcp: Failed to start ${name} — ${msg}`, "error");
        }
      }),
    );"""
NEW = """    // Start all eager servers concurrently without blocking the parent session.
    // Child sessions wait so strict tool allowlists see every eager MCP tool.
    const eagerStartup = Promise.allSettled(
      eagerServers.map(async ([name]) => {
        try {
          await manager.startServer(name, ctx.cwd);
        } catch (err) {
          const msg = err instanceof McpError ? err.userMessage : String(err);
          ctx.ui.notify(`pi-mcp: Failed to start ${name} — ${msg}`, "error");
        }
      }),
    );
    if (process.env.PI_SUBAGENT_DEPTH) await eagerStartup;"""


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} INDEX_TS", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Failed to read {path}: {exc}", file=sys.stderr)
        return 1

    candidates = [candidate for candidate in (OLD, LEGACY) if candidate in source]
    if source.count(NEW) == 1 and not candidates:
        return 0
    if len(candidates) != 1 or source.count(candidates[0]) != 1 or NEW in source:
        print(f"Pi MCP background patch source drift in {path}", file=sys.stderr)
        return 1

    path.write_text(source.replace(candidates[0], NEW), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
