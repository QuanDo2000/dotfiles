---
name: "efficient-subagent-use"
description: "Decide when and how to delegate for higher parallel performance without wasting tokens; use for non-trivial tasks with potentially independent work lanes"
version: 5
created: "2026-08-07"
updated: "2026-08-18"
---
## When to Use
Use before delegating non-trivial research, coding, review, or validation. Skip it for tiny requests or work that is inherently serial. The goal is lower wall-clock time without increasing token use unnecessarily.

This skill owns delegation decisions, lane sizing, and cost control; harness-specific skills own execution APIs and mechanics.

## Procedure
1. Delegate only when there are at least two independent substantial lanes, or one bounded lane can run while the parent continues useful work. If startup/context overhead is comparable to doing the task directly, do it directly.
2. Before launching, list available agents. Choose the cheapest capable role/model and normally 1–3 children; use more only when distinct risk or breadth justifies each lane.
3. Check active and completed runs for the same lane and unchanged target revision. Reuse its artifact or resume its retained child; relaunch only when the target or required evidence changes.
4. Parallelize read-only recon, research, review, and validation. Keep one writer per worktree unless writers have intentionally isolated worktrees.
5. Launch asynchronously when supported. Continue useful parent work; wait only when same-turn results are required.
6. Pass only governing matched skills through the child `skill` field; do not enable global skill inheritance. Builtin Pi roles do not inherit the discovered skill catalog.
7. Give each child a narrow compact contract: goal, only necessary files/evidence, success criteria, hard constraints, validation, output shape, and stop rule. Prefer fresh context unless conversation history is essential.
8. For read-only scouts and reviewers, set `agentContract: { version: 1 }`, omit `acceptance`, and request only findings, exact paths, confidence or coverage, and residual risks. Do not paste an acceptance schema. Keep default checked or review-required acceptance for mutation workers; the parent runs validation.
9. Synthesize results once, resolve disagreements from primary evidence, perform final verification in the parent, and stop spawning when enough evidence exists.

## Pitfalls
- Do not delegate tiny lookups, tightly serial steps, duplicate parent work, or clone prompts that produce redundant answers.
- Do not fork full parent context by default; copied history wastes tokens and biases independent review.
- Do not run parallel writers in one worktree.
- Do not keep children searching after the success criteria are met or launch reviewers merely for ceremony.
- Async does not mean unattended completion: the parent still owns synthesis, decisions, and verification.

## Verification
1. Every child has a distinct lane and necessary output.
2. No two writers share a worktree.
3. Parent continues useful work while async children run or returns control rather than polling.
4. Final answer uses child evidence without duplicating their full prose.
5. For substantial fleets, inspect `/subagent-cost` and reduce fanout/context if cost outweighs saved time.