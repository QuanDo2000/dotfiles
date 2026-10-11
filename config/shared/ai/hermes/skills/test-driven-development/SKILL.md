---
name: test-driven-development
description: "Use for behavior-changing code or bug fixes."
version: 1.3.0
author: Hermes Agent (adapted from obra/superpowers)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [testing, tdd, development, quality, red-green-refactor]
    related_skills: [systematic-debugging, subagent-driven-development]
---

# Reusable Execution and Focused Verification

Build the working capability, not a growing collection of one-off tests. Prefer a small number of real-flow checks through actual entry points. Test count and coverage percentage are not completion criteria.

## Generalize repeated execution patterns

- Inspect existing tools, native APIs, and repository runners first. Reuse them before creating another wrapper or fixture.
- When the same execution problem recurs, fix it once in a retained shared tool: process supervision, deadlines, bounded capture, cleanup, source binding, or result validation. Give callers a small explicit interface instead of copying orchestration and checks into each task.
- Build only for observed callers and failure modes. Prefer a helper or command over a framework; use a framework when existing repeated patterns justify it. Keep the executable source and invocation with the tool, not only its reports.
- Validate the shared tool through its real entry point with a representative success and the important failure paths. Consumers normally need only an integration check of their changed use, not a fresh proof of every unchanged tool invariant.
- Reuse is not blanket trust: changes to ownership, cleanup, limits, permissions, persistence, or source/runtime binding require focused verification of the affected contract. Preserve security, data-loss prevention, rollback, and required repository gates.

## Choose the minimum useful checks

- Before implementation, name the user-visible outcome and credible failures. Choose the smallest existing check that can catch them.
- Do not add unit tests by default, duplicate E2E assertions, or create a new fixture for every edit. Add a focused test only for an important uncovered correctness or safety failure.
- Batch related edits into a coherent change, then run affected checks. Do not rerun the full suite after every edit, handoff, or prose change. During development, run a targeted check when its result will change the next implementation decision.
- Reuse passing results for an unchanged tested component when its inputs, dependencies, environment, and relevant contract remain unchanged, even if unrelated files or the overall revision changed. State the checked scope and why it remains applicable; never describe an old full-suite run as a pass on a new head. Required exact-head gates still run on the final head.
- Assert observable output, durable state, exit status, or a boundary contract with independently derived expectations. Do not test private structure or grep source text merely to prove an edit happened.

## Bug fixes: one symptom reproducer

1. Reuse or create one reproducer for the reported symptom. Run it against the baseline and confirm failure for the intended reason, not a setup error.
2. Fix the shared root cause, batch related corrections, and run the same reproducer against the patched revision under equivalent conditions: baseline fails, patched passes.
3. Rerun only checks affected by subsequent behavior changes, plus applicable final repository gates. Do not repeat the baseline or recreate the harness for every refinement unless the reproducer or relevant assumptions changed.

Preserve unrelated work and baseline failure evidence. If a safe baseline run is unavailable, disclose that limitation; do not manufacture RED or claim test-first execution retroactively.

## Safe execution and completion

Use disposable state or an approved test environment. Production data, credentials, deployments, paid services, one-shot allowances, and explicit approval boundaries remain protected. Exercise real components; disclose unavoidable substitutions and unavailable coverage. Mock-backed checks are not E2E evidence.

Retain the shared executable tool and a repeatable command, prerequisites, checked scope, expected/actual outcome, and inspectable result. Use existing runner output rather than a separate evidence framework. Redact secrets and private data. A screenshot alone does not prove hidden state or safety properties.

At completion, run the smallest affected authoritative checks and applicable repository gates on the final revision. Inspect actual exit status and relevant output; report passed, failed, reused, skipped, and unverified checks. Child reports alone are not verification.

Configuration may use native validators. Prose needs review, not new substring tests or unrelated runtime trials. For instruction changes, use a small representative consuming-agent scenario only when an existing harness is available; otherwise report static review. Do not build a new evaluation harness just to validate wording.
