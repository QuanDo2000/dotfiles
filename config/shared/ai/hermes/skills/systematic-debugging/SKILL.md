---
name: systematic-debugging
description: "Use when diagnosing bugs, test failures, or unexpected behavior."
version: 1.1.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [debugging, troubleshooting, problem-solving, root-cause, investigation]
    related_skills: [test-driven-development, writing-plans, subagent-driven-development]
---

# Systematic Debugging

Locate the likely failing boundary using the cheapest available evidence. Prefer a fix at the shared cause, then verify the symptom and affected contracts. Label an unproven cause provisional.

## Establish facts

Check current state and relevant changes; validate paths and object identities before acting. For multi-component flows, inspect the suspected boundary and add diagnostics only when authorized, without exposing secrets. For service failures, compare the interactive and service environments, including the resolved interpreter.

Investigation-only requests prohibit persistent changes, including config edits, permission changes, restarts, cache clears, media rewrites, and database writes. Report blocked evidence and the next minimal check; do not invent completed reproduction steps.

Do not infer an individual cause from a combined experiment without evidence. Reassess data/control flow when repeated attempts reveal unclear ownership; ask before broadening mutation authority.

For performance: record a repeatable workload/environment and baseline, profile one hot path, set an improvement target and regression budget, then make one reversible change. Run correctness checks before/after and repeat the same workload enough to expose noise. Keep only measured improvements within the budget; revert only your own failed experiment.

## Fix and verify

Trace impacted callers and prefer a shared-cause fix. Use `test-driven-development` for symptom verification, then run affected and required checks under the global verification policy.

When evidence is missing or diagnosis remains uncertain, state the gap and continue useful bounded work within scope. Ask only before work that needs broader authority. Report the evidence versus hypothesis, smallest fix, validation, and residual risk. Use native search/read/terminal tools; delegate only independent substantial investigations under the global delegation policy.
