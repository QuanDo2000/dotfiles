---
name: plan
description: Write a markdown plan to .hermes/plans/; no execution.
version: 2.0.0
author: Hermes Agent (writing-craft adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [planning, plan-mode, implementation, workflow, design, documentation]
    related_skills: [subagent-driven-development, test-driven-development, requesting-code-review]
---

# Plan Mode

Plan only. Inspect with read-only tools; do not implement, run mutating commands, commit, push, or take external actions. The only permitted project write is the requested plan markdown file.

Use `writing-plans` for the content: goal, exclusions, assumptions, approach, exact target paths, independently verifiable steps/dependencies, validation, risks, and open decisions as relevant. Do not pre-implement the task in prose.

Save with `write_file` to the explicit user-requested path, or the runtime's designated path when the user supplied none. Otherwise use `.hermes/plans/YYYY-MM-DD_HHMMSS-<slug>.md` relative to the active backend workspace (local or remote). The default directory never overrides an explicit user path. Keep the planning-only write boundary regardless of location.

Infer a bare `/plan` request from the current conversation; ask briefly only if genuinely ambiguous. Reply with a concise summary and saved path, then stop without executing or committing the plan.
