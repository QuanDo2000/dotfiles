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

Establish the failing boundary and test one causal hypothesis before fixing production state.

## Establish facts

1. Read the complete error and exact command/output. Reproduce the smallest failure; if intermittent, record conditions rather than guessing.
2. Check live state and relevant recent changes. Validate paths and object identities before inspecting generated artifacts; historical reports are leads, not current proof.
3. Trace incorrect values/state backward through callers and component boundaries. Compare one nearby working path and only relevant differences.
4. For multi-component flows, inspect input/output/configuration at the suspected boundary; expand only when evidence requires it. Add targeted diagnostics only when authorized, without exposing secrets.
5. For service failures, compare interactive and service environments: unit/ExecStart, shebang, resolved interpreter/binary, and service-manager environment. Installation under one interpreter does not prove the service uses it.

Investigation-only requests prohibit persistent changes, including config edits, permission changes, restarts, cache clears, media rewrites, and database writes. Report blocked evidence and the next minimal check; do not invent completed reproduction steps.

## Test one hypothesis

State: “X is the cause because evidence Y; check Z distinguishes it.” Run the cheapest discriminating check, changing one variable. Discard disproved hypotheses rather than stacking fixes. Reassess the data/control flow when repeated attempts reveal new coupling or unclear ownership; ask before broadening mutation authority.

For performance: record a repeatable workload/environment and baseline, profile one hot path, set an improvement target and regression budget, then make one reversible change. Run correctness checks before/after and repeat the same workload enough to expose noise. Keep only measured improvements within the budget; revert only your own failed experiment.

## Fix and verify

Trace impacted callers and fix the shared cause, not symptoms in sibling callers. Use `test-driven-development` for the original symptom's regression, then apply the smallest authorized fix without bundled cleanup. Run the focused reproducer and impacted/required checks under the global verification policy.

Stop when necessary evidence is unavailable, diagnosis remains uncertain, or safe work requires broader scope/approval. Report the failing boundary, evidence versus hypothesis, smallest fix, validation, and residual risk. Use native search/read/terminal tools; delegate only independent substantial investigations under the global delegation policy.
