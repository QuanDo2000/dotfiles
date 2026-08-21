---
name: verification-before-completion
description: Use before claiming completion, committing, or moving on; match each claim to fresh authoritative evidence
---

# Verification Before Completion

**No completion claim without fresh evidence for that claim.**

## Gate

1. List the claims being made.
2. Map each claim to the smallest authoritative command or live-state check.
3. Run it on the current revision/state.
4. Read exit status, failure count, and relevant output.
5. Report exactly what passed, failed, was skipped, or remains unverified.

Examples:

| Claim | Evidence |
|---|---|
| bug fixed | original reproducer plus focused regression |
| tests pass | named test command with zero failures |
| build works | actual build exits zero |
| agent completed | inspect live diff/artifact, then run validation |
| requirements met | check each requirement, not merely test status |
| remote side effect succeeded | read back URL/ID/state from source |

## Efficiency

- During iteration, run focused checks.
- Run broad required suites once after the final change when the impact surface warrants them.
- Reuse a result only while revision, inputs, environment, and relevant live state are unchanged.
- Do not rerun an expensive unchanged gate merely to refresh wording.
- Child reports, old logs, linter success, partial tests, and “should work” are not substitutes for the needed evidence.

## Delegation

Treat child output as a claim. Verify its paths, diff, and commands independently before reporting success. Static reviewers inspect supplied evidence; they do not run validation.

## Final report

Name commands/checks and observed totals. Qualify partial verification explicitly; never hide skipped platforms, inaccessible state, or residual risk.
