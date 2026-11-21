---
name: writing-plans
description: "Use when writing verifiable implementation plans."
version: 1.1.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [planning, design, implementation, workflow, documentation]
    related_skills: [subagent-driven-development, test-driven-development, requesting-code-review]
---

# Writing Implementation Plans

Use when a requested plan or a consequential handoff needs implementation detail; do not require a plan for every edit.
Inspect the relevant current code, requirements, and constraints before proposing changes; reference the existing spec or requirement source when one exists.
State the goal, exclusions, assumptions, and unresolved decisions.
Split work into independently verifiable outcomes with dependencies; do not impose fixed durations.
For each outcome, name exact target paths, the intended behavior, and the smallest authoritative verification command. Before handing off, check that every in-scope requirement maps to an outcome and that shared interfaces agree; expose gaps instead of inventing decisions.
Label expected results as expectations, not observed output. Do not invent exact pass counts.
Include code only when it resolves a non-obvious interface or algorithm; do not pre-implement the whole change in prose.
Preserve security, data-loss, concurrency, and migration constraints next to the affected step.
Use the requested save path or the repository's established convention. For planning-only requests, follow `plan` for its write boundary and `.hermes/plans/` location; deliver the plan without committing or implementing it. When implementation is already authorized, use the plan as an internal checkpoint and proceed without asking for plan approval. Include the plan in normal delivery if it is explicitly in scope as a tracked deliverable.
Resolve low-risk reversible choices from current requirements and repository conventions. Ask only for material unresolved decisions or missing authority, not routine sequencing; batch independent related questions.
Carry the approved outcome, permitted effects, exclusions and original budgets into implementation. Continue necessary in-scope edits, tests, review and corrections without milestone reapproval; do not start adjacent backlog work or renew exhausted allowances.
Delegation and test strategy depend on task risk and available tools, not a mandatory itinerary.
