# Reviewing recent commits and jj-managed checkouts

Use this reference when the user asks for a follow-up review like “All points were fixed, anything else?” and the working tree is already clean.

## Pattern

1. Reconstruct the review scope before saying there is nothing to review:
   - Search prior session context if the user references a project or previous review.
   - Locate the repo and inspect recent commits.
   - If `git diff` and `git diff --cached` are empty, review an explicit recent range such as `HEAD~N..HEAD` based on the relevant commits.
2. Verify the repo state:
   - `git status --porcelain=v1`
   - `git status --short --branch`
   - `git log --oneline -5`
3. For jj-managed repositories, Git may report a detached HEAD even when the checkout is expected:
   - Report it neutrally as “Git reports detached HEAD / jj-managed checkout” rather than treating it as a failure.
   - Do not block review solely because the worktree is clean or detached.
4. Run the normal review gates against the reconstructed range:
   - `git diff --check <range>`
   - project tests/lint/vet/format checks
   - added-line security scan over `git diff <range>`
   - independent reviewer if the change is non-trivial.
5. Final response should distinguish blockers from optional polish.

## Example from my-server

Recent commits added `/admin/health` session counts: active sessions, successful logins in the last 24h, and failed logins in the last 24h. The working tree was clean, so the review used `HEAD~3..HEAD`. Checks included `go test ./...`, `go vet ./...`, `gofmt -l` on touched files, `git diff --check HEAD~3..HEAD`, a security-pattern scan over `git diff HEAD~3..HEAD`, and an independent review. No blockers were found; optional polish was adding an older-than-24h audit-row test and surfacing count-query errors instead of silently showing zero.