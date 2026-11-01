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
# 0.99.2 moves the same input boundary out one indentation level.
LATE_STEERING_099 = LATE_STEERING_086.replace("            ", "        ")
LATE_STEERING_099_PATCHED = "\n".join(
    line[4:] for line in LATE_STEERING_086_PATCHED.splitlines()
)
REPLACEMENTS_099 = replacements(
    (SUCCESS_EMIT, ERROR_EMIT.replace("aborted: false,", "aborted,")),
    (LATE_STEERING_099, LATE_STEERING_099_PATCHED),
)


# Published 1.4.0 CLI uses a minified AgentSession, separate from the SDK.
# Match complete event/input boundaries, not compiler-generated chunk filenames.
BUNDLE_SUCCESS = 'this._emit({type:"compaction_end",reason,result,aborted:!1,willRetry})'
BUNDLE_ERROR = 'this._emit({type:"compaction_end",reason,result:void 0,aborted,willRetry:!1,errorMessage:errorMessage5})'
BUNDLE_INPUT = 'let{text:currentText,images:currentImages}=processedInput,expandedText=currentText;'
BUNDLE_REPLACEMENTS = tuple(
    (emit, 'this._autoCompactionAbortController=void 0,' + emit)
    for emit in (BUNDLE_SUCCESS, BUNDLE_ERROR)
) + ((BUNDLE_INPUT,
      'if(this.isStreaming&&!this.agent.state.isStreaming)await this.waitForIdle();' + BUNDLE_INPUT),)


def patch_source(source, path, selected):
    states = []
    for original, replacement in selected:
        patched_count = source.count(replacement)
        original_count = source.replace(replacement, "").count(original)
        if patched_count == 1 and original_count == 0:
            states.append("patched")
        elif patched_count == 0 and original_count == 1:
            states.append("original")
        else:
            states.append("drift")

    if all(state == "patched" for state in states):
        return source
    upgrade = (
        selected is REPLACEMENTS
        and all(state == "patched" for state in states[:-1])
        and states[-1] == "original"
    )
    if not (all(state == "original" for state in states) or upgrade):
        raise ValueError(f"Pi compaction patch source drift in {path}")
    for state, (original, replacement) in zip(states, selected):
        if state == "original":
            source = source.replace(original, replacement)
    return source


def sdk_replacements(source):
    selected = REPLACEMENTS_086 if LATE_STEERING_086 in source else REPLACEMENTS
    # The patched input block no longer contains the original adjacent lines.
    if LATE_STEERING_086_PATCHED in source:
        selected = REPLACEMENTS_086
    if LATE_STEERING_099 in source or LATE_STEERING_099_PATCHED in source:
        selected = REPLACEMENTS_099
    return selected


def bundle_target(directory):
    candidates = [path for path in (directory / "chunks").glob("*.js")
                  if "async _runAutoCompaction(" in path.read_text(encoding="utf-8")]
    if len(candidates) != 1:
        raise ValueError(f"Pi compaction patch source drift in {directory}: expected one bundled AgentSession")
    path = candidates[0]
    # Verify this is the actual CLI runtime's owning chunk, not a stale spare.
    if ('"./cli-runtime.js"' not in (directory / "cli.js").read_text(encoding="utf-8")
            or f'from"./chunks/{path.name}"' not in
            (directory / "cli-runtime.js").read_text(encoding="utf-8")):
        raise ValueError(f"Pi compaction patch source drift in {directory}: CLI ownership changed")
    return path


def write_atomic(path, result):
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


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {Path(sys.argv[0]).name} AGENT_SESSION_JS [BUNDLE_DIR]", file=sys.stderr)
        return 1
    try:
        sdk = Path(sys.argv[1])
        source = sdk.read_text(encoding="utf-8")
        updates = [(sdk, source, patch_source(source, sdk, sdk_replacements(source)))]
        if len(sys.argv) == 3:
            bundle = bundle_target(Path(sys.argv[2]))
            source = bundle.read_text(encoding="utf-8")
            updates.append((bundle, source, patch_source(source, bundle, BUNDLE_REPLACEMENTS)))
        # Validate every target before changing either; rejected drift leaves both untouched.
        for path, original, result in updates:
            if original != result:
                write_atomic(path, result)
    except (OSError, ValueError) as exc:
        print(f"Pi compaction patch source drift: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
