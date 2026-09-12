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
Inspect the relevant current code, requirements, and constraints before proposing changes.
State the goal, exclusions, assumptions, and unresolved decisions.
Split work into independently verifiable outcomes with dependencies; do not impose fixed durations.
For each outcome, name exact target paths, the intended behavior, and the smallest authoritative verification command.
Label expected results as expectations, not observed output. Do not invent exact pass counts.
Include code only when it resolves a non-obvious interface or algorithm; do not pre-implement the whole change in prose.
Preserve security, data-loss, concurrency, and migration constraints next to the affected step.
Use the requested save path or the repository's established convention; never commit the plan automatically.
For planning-only requests, use `plan` for its write boundary and `.hermes/plans/` location.
Offer execution only after delivering the plan. Delegation and test strategy depend on task risk and available tools, not a mandatory itinerary.
