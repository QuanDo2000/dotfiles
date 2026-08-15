#!/usr/bin/env python3
"""Patch pi-mcp-extension so eager servers start without blocking Pi startup."""

import sys
from pathlib import Path

OLD = """    // Start all eager servers concurrently
    await Promise.allSettled("""
NEW = """    // Start all eager servers concurrently without blocking session startup
    void Promise.allSettled("""


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

    if source.count(NEW) == 1 and OLD not in source:
        return 0
    if source.count(OLD) != 1 or NEW in source:
        print(f"Pi MCP background patch source drift in {path}", file=sys.stderr)
        return 1

    path.write_text(source.replace(OLD, NEW), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
