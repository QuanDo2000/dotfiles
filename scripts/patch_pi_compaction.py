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
                    willRetry: false,"""
LATE_STEERING = """                if (inputResult.action === "transform") {
                    currentText = inputResult.text;
                    currentImages = inputResult.images ?? currentImages;
                }
            }
            // Expand skill commands (/skill:name args) and prompt templates (/template args)"""
LATE_STEERING_PATCHED = """                if (inputResult.action === "transform") {
                    currentText = inputResult.text;
                    currentImages = inputResult.images ?? currentImages;
                }
            }
            // Input hooks can outlive the core agent run while session post-run work is still settling.
            // Wait before classifying delivery so late steering starts a new run instead of stranding.
            if (this.isStreaming && !this.agent.state.isStreaming) {
                await this.waitForIdle();
            }
            // Expand skill commands (/skill:name args) and prompt templates (/template args)"""
PATCHES = (CANCEL_EMIT, ABORT_EMIT, SUCCESS_EMIT, ERROR_EMIT)
LATE_STEERING_086 = """            const { text: currentText, images: currentImages } = processedInput;
            // Expand skill commands (/skill:name args) and prompt templates (/template args)"""
LATE_STEERING_086_PATCHED = LATE_STEERING_086.replace(
    "            // Expand skill commands",
    """            // Input hooks can outlive the core agent run while session post-run work is still settling.
            // Wait before classifying delivery so late steering starts a new run instead of stranding.
            if (this.isStreaming && !this.agent.state.isStreaming) {
                await this.waitForIdle();
            }
            // Expand skill commands""",
)


def replacements(emits, late_input):
    return tuple(
        (emit, f"{emit[: len(emit) - len(emit.lstrip())]}{CLEAR}\n{emit}") for emit in emits
    ) + (late_input,)


REPLACEMENTS = replacements(PATCHES, (LATE_STEERING, LATE_STEERING_PATCHED))
# 0.86.1 consolidates cancellation, abort, and error into a single catch event.
REPLACEMENTS_086 = replacements(
    (SUCCESS_EMIT, ERROR_EMIT.replace("aborted: false,", "aborted,")),
    (LATE_STEERING_086, LATE_STEERING_086_PATCHED),
)


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

    selected = REPLACEMENTS_086 if LATE_STEERING_086 in source else REPLACEMENTS
    # The patched input block no longer contains the original adjacent lines.
    if LATE_STEERING_086_PATCHED in source:
        selected = REPLACEMENTS_086
    states = []
    for original, replacement in selected:
        if source.count(replacement) == 1:
            states.append("patched")
        elif source.count(replacement) == 0 and source.count(original) == 1:
            states.append("original")
        else:
            states.append("drift")

    if all(state == "patched" for state in states):
        return 0
    upgrade = (
        selected is REPLACEMENTS
        and all(state == "patched" for state in states[:-1])
        and states[-1] == "original"
    )
    if not (all(state == "original" for state in states) or upgrade):
        print(f"Pi compaction patch source drift in {path}", file=sys.stderr)
        return 1

    result = source
    for state, (original, replacement) in zip(states, selected):
        if state == "original":
            result = result.replace(original, replacement)

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
