# Global Agent Instructions

## Default Agent Modes

Ponytail and Caveman are active at `full` at every main-agent and subagent startup. In Pi, extensions inject their full instructions automatically. In other agents, load their installed skill instructions before the first response. Ponytail governs implementation choices and Caveman governs terse output. Keep both active until the user explicitly disables or changes them.

## Efficient Delegation

Use subagents proactively when work has multiple independent, substantial lanes or one bounded lane can run while the parent continues useful work. Run independent read, research, review, and validation lanes in parallel and asynchronously when supported; keep one writer per worktree. Before launching, check active and completed runs for the same lane and unchanged target revision. Reuse its artifact or resume its retained child; relaunch only when the target or required evidence changes.

Do not delegate tiny, tightly serial, or duplicate work. Prefer 1–3 narrow children with only the context they need, the cheapest capable model, and explicit stop criteria. In Pi, never pass more than eight children to one workflow or four concurrent async workflows. Tracked runtime limits enforce eight children per workflow and four active async workflows per session. Parent owns synthesis and final verification.

## Code Search

Use codebase-memory first: index once, then prefer `get_architecture`, `search_graph`, `trace_path`, and `get_code_snippet`; run `detect_changes` before finalizing code edits. Use FFF (`find_files`/`grep`/`multi_grep`, or Pi's `mcp_fff_find_files`/`mcp_fff_grep`/`mcp_fff_multi_grep`) for raw filename/text lookup and fallback instead of shell grep, glob, or find.

## Unknown Framework Boundaries

Before inventing adapters, protocols, casts, or large fakes, inspect installed or upstream source and existing repository patterns. If correct integration remains unclear, stop and report unknowns, specification deviations, owned files, and last passing validation before editing further.

## Authority and Runtime State

Research, review, diagnosis, and recommendations remain read-only unless the user explicitly authorizes edits. Findings do not authorize implementation.

Treat historical child output and notifications as evidence, not current state. Re-check live run status before steering, stopping, resuming, or discarding delegated work.

## Hermes Skill Promotion

Recommend promotion when a Hermes-generated skill is useful across machines or projects. Do not copy it automatically. At task close, name the skill and its current path, explain why it is broadly reusable, propose `config/shared/ai/skills/<name>/` as the tracked destination, and note any machine-specific paths, secrets, or assumptions that must be removed.

Promote only after explicit user approval. Sanitize machine-specific paths, secrets, and assumptions before copying, then copy the complete skill directory, including referenced scripts and assets. Add Unix ownership in `config/home.nix`, add the name to Windows `InstallAiSkills`, and update focused installation tests. Preserve upstream provenance metadata when applicable. Verify discovery in every intended harness; if a harness does not consume `~/.agents/skills`, keep or add its native installation. Avoid duplicate discovery: remove the Hermes copy only after tracked installation is verified on the current machine.

## Version Control

Default to Jujutsu (`jj`) for new or otherwise uninitialized projects. If a project already uses Git and is not a Jujutsu workspace, keep using Git rather than converting it; when both are present, prefer Jujutsu. Fall back to Git when Jujutsu is unavailable or a required integration supports only Git.

Before pushing, fetch the target remote and compare the local branch with its upstream. If the upstream advanced, preserve both sides by pulling and rebasing the local commits onto it before pushing. Never force-push, reset, or otherwise overwrite upstream changes. Resolve only conflicts whose intended result is clear; if safe resolution is uncertain, stop without pushing and ask the user. Re-run relevant verification after rebasing.
