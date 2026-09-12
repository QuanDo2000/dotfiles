---
name: subagent-driven-development
description: "Use when delegating approved implementation work."
version: 1.1.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [delegation, subagent, implementation, workflow, parallel]
    related_skills: [writing-plans, requesting-code-review, test-driven-development]
---

# Subagent-Driven Development

Use for an approved implementation plan with independent substantial work lanes; execute tiny or tightly coupled work directly.
Check the active runtime's delegation capability. If unavailable, work directly or use an explicitly approved supported runtime; do not invent `delegate_task` calls.
Give each child one outcome, exact workspace/allowed paths, relevant evidence, exclusions, stop conditions, and required output.
One writer per worktree; readers may share it. Keep task boundaries at independently verifiable outcomes, not fixed minute counts.
Reuse a recoverable child and its artifacts rather than restarting unchanged work.
The parent resolves dependencies and verifies each requested result against current source and authoritative checks.
Use one read-only reviewer for spec, correctness, and security. Add another only for a named distinct risk.
Pass reviewers the requirements, complete diff, relevant source, and validation evidence; do not ask static reviewers to run commands.
Confirmed findings go back to the implementation owner. The parent may make a small authorized repair directly.
Run focused checks during iteration and required integration checks on the final revision.
Do not stage, commit, push, or broaden the write scope without authorization.
Use `multi-agent-orchestration` for runtime selection, recovery, model routing, and durable-worker requirements.

## Further reading (load when relevant)

When the orchestration involves significant context usage, long review loops, or complex validation checkpoints, load these references for the specific discipline.
The task contract above takes precedence over their legacy delegation, read-depth, and commit examples: parent verification and small authorized repairs remain allowed, and examples do not authorize commits or additional writes.

- **`references/context-budget-discipline.md`** — Four-tier context degradation model (PEAK / GOOD / DEGRADING / POOR), read-depth rules that scale with context window size, and early warning signs of silent degradation. Load when a run will clearly consume significant context (multi-phase plans, many subagents, large artifacts).
- **`references/gates-taxonomy.md`** — The four canonical gate types (Pre-flight, Revision, Escalation, Abort) with behavior, recovery, and examples. Load when designing or reviewing any workflow that has validation checkpoints — use the vocabulary explicitly so each gate has defined entry, failure behavior, and resumption rules.

Both references adapted from gsd-build/get-shit-done (MIT © 2025 Lex Christopherson).
