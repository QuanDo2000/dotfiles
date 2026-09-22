---
name: multi-agent-orchestration
description: "Use when routing work across subagent runtimes."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [delegation, subagents, orchestration, codex, pi, debugging]
---

# Multi-Agent Orchestration

Choose the simplest supported mechanism by ownership and lifecycle. Use `references/runtime-routing.md` for the selection table and live checks; never assume a runtime or extension is installed. Mechanical counting/filtering belongs in local tools, not reasoning children.

## Dispatch contract

Give each child one independent substantial outcome, exact workspace/sources, necessary observed state, exclusions, writable root (if any), stop criteria/budget, and output/evidence requirements. Precompute shared inventories once. Do not split by arbitrary file ranges or delegate tiny, duplicate, or serial tasks.

One writer per worktree; readers may share. Prefer the cheapest capable model and asynchronous work when the parent has useful independent work. Parent owns synthesis and verifies source, tests, external changes, IDs/URLs, and process state rather than trusting summaries.

Before dispatch, check active/completed runs for the same target. Reuse artifacts or recover the existing child instead of duplicating work. For a child writing elsewhere while inspecting a live tree, record and recheck the live tree's status. If it writes outside its assigned root, stop using those side effects and restore only clearly attributable changes; preserve unrelated work and ask when attribution is uncertain.

Static reviewers receive complete evidence up front and never run commands. Use one reviewer by default; another needs a distinct risk. See `references/reviewer-evidence-handoffs.md` for evidence packets and recovery.

## Recover by lifecycle, not guesswork

Distinguish a child run deadline, parent wait timeout, iteration/tool budget, stalled provider/tool call, and owner-process loss. Inspect live state and durable artifacts before retrying. A wait timeout does not prove termination, and recent activity at a fixed cutoff suggests a deadline rather than a hang. Salvage evidence once, then narrow only the missing work.

For Hermes timeout diagnosis, use `references/delegation-timeout-diagnosis.md`. Keep cost limits intentional; do not change policy merely to hide an over-scoped child. Background processes are not durable queues; use persisted scheduling only when retry/survival/delivery requirements justify it.

## Cross-runtime installation boundary

Evaluation is not installation approval. Before adding a bridge, explain package/dependency execution, directionality, fresh versus existing session semantics, network/auth exposure, lifecycle/reload effects, workspace authority, and native alternatives. Obtain informed approval before installing. If corrected after a side effect, stop, disclose exact state, and wait rather than continuing or silently rolling back. Use `references/a2a-cross-runtime-setup.md` for staging and bidirectional verification.

## Conditional references

- `references/hermes-model-routing.md`: main, child, auxiliary, and fallback routing.
- `references/pi-model-routing.md`: effective role precedence, availability, auth, and managed state.
- `references/pi-concurrency-and-model-scope.md`: concurrency lifetimes and scope enforcement; version-specific claims require installed-source verification.
- `references/pi-tmux-agent-operations.md`: discover, inspect, and steer the correct existing pane.
- `references/subagent-portfolio-audit.md`: bounded evidence before disabling roles; diagnose orchestration waste first.

## Verify the changed contract

Run one bounded smoke child with exact sources/output, confirm scope and summary, and inspect resolved budget/routing. For async work, verify artifacts and completion notification, not process disappearance. For mutations inspect the diff and authoritative checks; for durable work verify ownership, retry state, and final delivery. Report untested runtime boundaries explicitly.
