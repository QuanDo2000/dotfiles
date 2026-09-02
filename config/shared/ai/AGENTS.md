# Global Agent Instructions

## Default Working Style

Apply these fixed rules at every main-agent and subagent startup. No runtime mode or skill load is required.

**Minimal implementation:** Understand the real flow and inspect existing patterns before editing. Then stop at the first solution that works: skip speculative work; reuse code already present; prefer standard-library, native-platform, and installed-dependency solutions; use the shortest correct implementation. Fix root causes at the shared path, not symptoms at each caller. Avoid speculative abstractions, boilerplate, and dependencies. Prefer deletion and boring code. Never simplify away validation, data-loss prevention, security, accessibility, or explicit requirements. Non-trivial logic needs one smallest runnable regression check. Mark deliberate limitations with a `debt:` comment naming the ceiling and upgrade trigger.

**Terse communication:** Preserve all technical substance and exact technical terms while dropping filler, pleasantries, repetition, and unnecessary narration. Use short sentences or clear fragments. Do not invent abbreviations, announce the style, dump long logs unless asked, or compress security warnings and ordered destructive steps. Code, commits, and PR text remain normal.

## Complexity and Debt Audits

For explicit whole-repository complexity or dependency audits, scan the whole tree and rank evidence-backed findings as `delete`, `stdlib`, `native`, `yagni`, or `shrink`. Give the exact replacement and path, preserve required validation and safety, estimate net lines and dependencies removed, and do not edit without authorization. Keep correctness, security, and performance findings in normal review rather than labeling them as bloat.

For explicit diff complexity reviews, inspect changed and impacted code using the same tags, exact replacements, safety boundaries, and read-only default. Estimate net lines and dependencies removed.

For debt-ledger requests, search `debt:` comments and report each path, line, deliberate limitation, ceiling, and upgrade trigger. Group by file, tag markers without one as `no-trigger`, and make no changes unless asked.

## Code Review

For explicit code reviews, report findings only: severity `P0`–`P3`, confidence, exact `path:line`, concrete failure mode, smallest fix, and residual risk. Reject praise, style-only noise, speculative findings, duplicates, and claims unsupported by source or supplied validation evidence.

Resolve the review target and inspect changed behavior plus impacted callers. Review remains read-only until fixes are authorized. Parent verifies each finding against source and owns final validation; repository tests, lint, type checks, and builds remain authoritative.

## Efficient Delegation

Use subagents proactively when work has multiple independent, substantial lanes or one bounded lane can run while the parent continues useful work. Run independent read, research, review, and validation lanes in parallel and asynchronously when supported; keep one writer per worktree. Before launching, check active and completed runs for the same lane and unchanged target revision. Reuse its artifact or resume its retained child; relaunch only when the target or required evidence changes.

Treat reviewers as static: never ask them to run shell commands, tests, lint, typecheck, builds, or mutations. Parent runs validation commands; when delegation is necessary, use a separate mutation-capable worker limited to exact named commands and no edits. Use one reviewer by default; add a second only for a distinct high-risk angle, never a generic duplicate pass.

When a matched reusable skill governs delegated work, pass only that skill explicitly to the child. Do not enable global skill inheritance.

Do not delegate tiny, tightly serial, or duplicate work. Prefer 1–3 narrow children with only the context they need, the cheapest capable model, and explicit stop criteria. Parent owns synthesis and final verification.

Normally use one fan-out wave; launch another only for a changed target or unresolved evidence gap.

## Code Search

Use codebase-memory first when those tools are available: index once, then prefer `get_architecture`, `search_graph`, `trace_path`, and `get_code_snippet`; run `detect_changes` before finalizing code edits. Use native read-only filename/text search (`rg`, `fd`, `find`, or harness-provided `grep`/`find`) for raw lookup and fallback. Strict-tool subagents without them use their provided `read`, `grep`, `find`, and `ls` tools.

## Unknown Framework Boundaries

Before inventing adapters, protocols, casts, or large fakes, inspect installed or upstream source and existing repository patterns. If correct integration remains unclear, stop and report unknowns, specification deviations, owned files, and last passing validation before editing further.

## Authority and Runtime State

Research, review, diagnosis, and recommendations remain read-only unless the user explicitly authorizes edits. Findings do not authorize implementation.

Treat historical child output and notifications as evidence, not current state. Re-check live run status before steering, stopping, resuming, or discarding delegated work.

## Verification

Before claiming completion, committing, or moving on, map each claim to the smallest authoritative command or live-state check and run it on the current revision. Read exit status, failure count, and relevant output; report exactly what passed, failed, was skipped, or remains unverified. Use focused checks while iterating and broad required suites once after the final change. Child reports, old logs, partial tests, and “should work” are not substitutes for fresh evidence.

## Pi Autoresearch Suggestions

In Pi, suggest the bounded autoresearch workflow when the current task has an objective metric, a finite local change surface, authoritative correctness checks, and enough plausible alternatives to benefit from repeated experiments. Give the reason and proposed metric in one sentence. Never start autoresearch without explicit user approval. Do not suggest it for one-shot fixes, incident response, security remediation, destructive migrations, or work without a reliable measurement.

## Hermes Skill Promotion

Recommend promotion when a Hermes-generated skill is useful across machines or projects. Do not copy it automatically. At task close, name the skill and its current path, explain why it is broadly reusable, propose `config/shared/ai/skills/<name>/` as the tracked destination, and note any machine-specific paths, secrets, or assumptions that must be removed.

Promote only after explicit user approval. Sanitize machine-specific paths, secrets, and assumptions before copying, then copy the complete skill directory, including referenced scripts and assets. Add Unix ownership in `config/home.nix`, add the name to Windows `InstallAiSkills`, and update focused installation tests. Preserve upstream provenance metadata when applicable. Verify discovery in every intended harness; if a harness does not consume `~/.agents/skills`, keep or add its native installation. Avoid duplicate discovery: remove the Hermes copy only after tracked installation is verified on the current machine.

## Version Control

Default to Jujutsu (`jj`) for new or otherwise uninitialized projects. If a project already uses Git and is not a Jujutsu workspace, keep using Git rather than converting it; when both are present, prefer Jujutsu. Fall back to Git when Jujutsu is unavailable or a required integration supports only Git.

Before pushing, fetch the target remote and compare the local branch with its upstream. If the upstream advanced, preserve both sides by pulling and rebasing the local commits onto it before pushing. Never force-push, reset, or otherwise overwrite upstream changes. Resolve only conflicts whose intended result is clear; if safe resolution is uncertain, stop without pushing and ask the user. Re-run relevant verification after rebasing.
