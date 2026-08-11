#!/usr/bin/env python3
"""Patch Pi's auto-compaction lifecycle so queued steering messages resume."""

import os
import stat
import sys
import tempfile
from pathlib import Path

CLEAR = "this._autoCompactionAbortController = undefined;"
CANCEL_EMIT = """                    this._emit({
                        type: "compaction_end",
                        reason,
                        result: undefined,
                        aborted: true,
                        willRetry: false,
                    });"""
ABORT_EMIT = """                this._emit({
                    type: "compaction_end",
                    reason,
                    result: undefined,
                    aborted: true,
                    willRetry: false,
                });"""
SUCCESS_EMIT = '            this._emit({ type: "compaction_end", reason, result, aborted: false, willRetry });'
ERROR_EMIT = """                this._emit({
                    type: "compaction_end",
                    reason,
                    result: undefined,
                    aborted: false,
                    willRetry: false,
                    errorMessage: reason === "overflow"
                        ? `Context overflow recovery failed: ${errorMessage}`
                        : `Auto-compaction failed: ${errorMessage}`,
                });"""
PATCHES = (CANCEL_EMIT, ABORT_EMIT, SUCCESS_EMIT, ERROR_EMIT)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} AGENT_SESSION_JS", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Failed to read {path}: {exc}", file=sys.stderr)
        return 1

    patched = tuple((emit, f"{emit[: len(emit) - len(emit.lstrip())]}{CLEAR}\n{emit}") for emit in PATCHES)
    patched_counts = tuple(source.count(replacement) for _, replacement in patched)
    if all(count == 1 for count in patched_counts):
        return 0
    if any(patched_counts) or any(source.count(emit) != 1 for emit in PATCHES):
        print(f"Pi compaction patch source drift in {path}", file=sys.stderr)
        return 1

    result = source
    for emit, replacement in patched:
        result = result.replace(emit, replacement)

    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(result)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
