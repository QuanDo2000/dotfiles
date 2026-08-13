#!/usr/bin/env python3
"""Patch pi-mcp-extension so eager servers start without blocking Pi startup."""

import os
import stat
import sys
import tempfile
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

    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(source.replace(OLD, NEW))
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
