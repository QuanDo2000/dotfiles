---
name: test-driven-development
description: Use for behavior-changing code or bug fixes.
---

# Test-First, Real-Flow Verification

Prove the behavior, not the implementation. Prefer a small number of tests that run the real workflow over many assertions about internal structure. Test count and coverage percentage are not completion criteria.

## Before implementation

1. Name the user-visible outcome and credible ways it could fail. Include relevant security, data-loss, and rollback risks; do not enumerate every imaginable case.
2. Inspect the actual entry point, dependencies, and existing checks. Choose the smallest boundary that can catch the failure.
3. For a complex feature, prefer an integration or E2E check through the real workflow. Use focused unit tests for logic or safety branches that are difficult, unsafe, or expensive to exercise end to end. Do not duplicate the same assertions at every layer.
4. Write the smallest failing example before changing production code. A bug fix starts with a reproducer for the reported symptom, not a test inferred from the proposed fix.

## RED → GREEN → simplify

- Run the focused check and confirm it fails for the intended missing or broken behavior, not a setup error.
- If it already passes, verify it against the revision without the fix in isolation; preserve existing work. Do not weaken expectations to manufacture RED. Report when RED cannot be established safely.
- Implement only what makes that example pass, at the shared root cause. No speculative options, abstractions, or cleanup.
- Run the check again. Simplify only after GREEN, then rerun affected checks.
- Repeat for the next important uncovered behavior, not for every function or line.

Exploration is allowed when an interface is unknown. Remove only your own throwaway exploratory changes before RED/GREEN. If implementation already exists, add the missing regression and establish RED against the prior revision when safe; never discard existing work or pretend the test was written first.

## What earns a test

Before writing an assertion, name the plausible defect it catches.

- Assert observable output, durable state, exit status, or a boundary contract. Use independently derived expectations, not the same helper that computes the actual result.
- Do not grep source text, split constant strings into many assertions, or lock down private structure merely to prove an edit happened. Exact text matters when it is the public contract, such as serialized output or protocol syntax.
- Exercise real components. Substitute only unavoidable external, nondeterministic, costly, or unsafe boundaries. Inspect the real interface first; preserve the side effects and response shape the tested flow consumes.
- Assert calls, arguments, and ordering only when they are the boundary contract. An assertion that a mock exists or returns its configured answer proves nothing.
- If mock setup becomes more complicated than the behavior, move to a real integration check rather than expanding the fake.
- Keep test-only scaffolding in tests. Do not add production APIs solely to satisfy a test.

## Repeatable evidence

For complex workflows, finish with a safe real-flow check and an inspectable artifact: a test report, captured CLI output, generated file, trace, or verified resulting state. Record the revision, exact command, relevant prerequisites/fixtures, expected outcome, and actual result so another person can repeat it. Reuse the existing runner's output; do not build an artifact framework. A screenshot alone does not prove hidden state or safety properties.

Use disposable state or an approved test environment. Do not touch production data, credentials, deployments, or paid services without authorization. Redact secrets and private data from retained artifacts. If the real flow is unavailable, say what was substituted and what remains unverified; a mock-backed pass is not an E2E pass.

## Completion

- Confirm the regression fails without the fix and passes with it, or disclose why RED was unavailable.
- Run impacted checks and applicable repository gates on the final revision. Read exit status, failure count, and relevant output; do not substitute a child report or old log for execution.
- Report passed, failed, skipped, and unverified checks with the evidence location or output. Reuse results only while their revision and inputs remain unchanged.

Configuration-only changes may use native parsing, evaluation, or the repository's existing validation instead of inventing a unit framework. Human prose needs review, not substring tests. For agent instructions, exercise representative consuming-agent scenarios when a harness is available; otherwise label the review as static and do not claim behavioral validation.
