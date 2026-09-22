# Review Output

State repository/PR and exact comparison base/head. Distinguish merge-base PR review from an exact-base commit comparison.

For each evidence-backed defect:

- **P0–P3 — title** (confidence)
- **Location:** `path:line` at reviewed head
- **Failure:** triggering condition and concrete consequence
- **Fix:** smallest correction
- **Residual risk:** what remains unknown or unverified

Report introduced defects only for diffs. Exclude praise, style preferences, speculation, and duplicate findings. If none qualify, say “No actionable findings” and name material review limitations; this is not approval or proof of correctness.

Report check evidence separately, including failed, skipped, and unverified checks. Static reviewers do not execute checks. Return this report privately unless publication was authorized; never post a second summary merely because a formal review was already posted.
