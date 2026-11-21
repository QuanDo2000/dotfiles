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

Delegate approved, independent substantial outcomes; do tiny or tightly coupled work directly. Verify the active runtime supports delegation, otherwise work directly or use an explicitly approved supported runtime.

Give each child one outcome, exact workspace/writable paths, relevant evidence, exclusions, stop conditions, and required output. Keep one writer per worktree; readers may share. Propagate current authorization, original budgets, global delivery policy and task-specific prohibitions to implementation owners; never broaden scope implicitly.

An approved implementation outcome includes necessary in-scope tests and corrections without milestone reapproval. Resolve low-risk reversible choices from requirements and repository conventions. Parent handles child evidence requests and review findings using existing authority; ask the user only for a material unresolved decision, missing authority or exhausted explicit allowance. Batch independent related questions, and continue independent authorized work while a separate phase is blocked.

Parent resolves dependencies, reuses recoverable children/artifacts, and verifies results against current source and authoritative checks. Parent-only review is enough for narrow, low-risk changes with clear validation only when no independent review is required. Use one independent static reviewer for substantial, complex, or high-risk changes or when required by governing instructions. A second needs a distinct, named high-risk angle. For unattended merge and scoped exceptions, apply the governing delivery policy to the exact final head.

Give static reviewers the requirements, complete diff, relevant source, and validation evidence for spec, correctness, and security review; never ask them to run commands. Confirmed findings return to the implementation owner; small authorized parent repairs are allowed. Refresh affected review/checks after changes.

Keep evidence bounded but sufficient for semantic verification, not just status summaries. Checkpoint exact revisions, completed work, blockers, and next steps when context becomes unreliable. For each checkpoint, state the passing condition, failure action, and safe resumption point. Defer an affected action if authority is missing or its scope is unclear; continue independent authorized work. Name material uncertainty and apply the governing scoped-exception rule to local defaults. Do not bypass external safeguards, renew budgets implicitly, alter exact-file contracts silently, or treat offline success as live/deployment permission. Planning-only and step-only restrictions remain binding.

Use `multi-agent-orchestration` for runtime selection, lifecycle recovery, routing, and durable-worker needs.

Checkpoint/context guidance adapted from gsd-build/get-shit-done (MIT © 2025 Lex Christopherson, https://github.com/gsd-build/get-shit-done).
