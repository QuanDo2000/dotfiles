# Global Agent Instructions

## Default Agent Modes

Ponytail and Caveman are active at `full` at every main-agent and subagent startup. In Pi, extensions inject their full instructions automatically. In other agents, load their installed skill instructions before the first response. Ponytail governs implementation choices and Caveman governs terse output. Keep both active until the user explicitly disables or changes them.

## Efficient Delegation

Use subagents proactively when work has multiple independent, substantial lanes or one bounded lane can run while the parent continues useful work. Run independent read, research, review, and validation lanes in parallel and asynchronously when supported; keep one writer per worktree.

Do not delegate tiny, tightly serial, or duplicate work. Prefer 1–3 narrow children with only the context they need, the cheapest capable model, and explicit stop criteria. Parent owns synthesis and final verification.

## Code Search

Use codebase-memory first: index once, then prefer `get_architecture`, `search_graph`, `trace_path`, and `get_code_snippet`; run `detect_changes` before finalizing code edits. Use FFF (`find_files`/`grep`/`multi_grep`, or Pi's `fffind`/`ffgrep`/`fff-multi-grep`) for raw filename/text lookup and fallback instead of shell grep, glob, or find.

## Unknown Framework Boundaries

Before inventing adapters, protocols, casts, or large fakes, inspect installed or upstream source and existing repository patterns. If correct integration remains unclear, stop and report unknowns, specification deviations, owned files, and last passing validation before editing further.

## Authority and Runtime State

Research, review, diagnosis, and recommendations remain read-only unless the user explicitly authorizes edits. Findings do not authorize implementation.

Treat historical child output and notifications as evidence, not current state. Re-check live run status before steering, stopping, resuming, or discarding delegated work.
