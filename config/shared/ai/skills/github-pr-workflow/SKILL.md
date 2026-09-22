---
name: github-pr-workflow
description: "Deliver authorized changes through GitHub pull requests and exact-head CI checks."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitHub, Pull-Requests, CI/CD, Git, Automation, Merge]
    related_skills: [github-auth, github-code-review]
---

# GitHub PR Workflow

Use the governing implementation, delivery, signing, and merge policy. This adapter does not expand authorization: research/review remains read-only; authorized implementation may carry automatic task-branch delivery under that policy. Explicit no-commit/no-push restrictions win. Merge requires the governing repository allowlist or explicit approval, never just matching an owner name.

## Prepare and implement

1. Verify the checkout, remote identity, default/base branch, current full SHA, and staged/unstaged/untracked state. Check for an existing task branch/PR before creating duplicates. Distinguish forks from the intended repository.
2. Isolate authorized work in a task branch/worktree or native JJ workspace according to repository policy. Preserve unrelated changes and never publish to a default/protected branch directly.
3. Name observable behavior and credible failures, then use the matching test/debug workflow. Run focused and required repository checks on the final candidate. Static review and CI supplement—not replace—those checks.
4. Reinspect the diff after tests/hooks. Stage explicit task paths or reviewed hunks, never `git add .` or `git add -A`. Inspect the staged diff before committing. Preserve required signing; on an authentication blocker, stop and ask for user-side unlocking, not unsigned fallback.

## Publish the task branch

- Fetch and compare upstream before push. Integrate remote advances without overwriting either side; stop on ambiguous conflicts. Rerun affected checks after integration. Never force-push or bypass protections.
- Push only reviewed task commits to the verified task branch. Read back the published full SHA and compare it with the validated candidate; an unrelated concurrent commit must not ride along.
- Inspect existing PRs for the exact head/base before creation. Use `gh pr create --repo OWNER/REPO --base BASE --head BRANCH --title TITLE --body-file FILE`; for a fork, resolve the correct owner-qualified head explicitly.
- Keep the body to problem, scoped change, actual verification, unverified coverage, and relevant risk/rollback. Templates under `templates/` are optional structure, not claims that checks passed. Follow repository title conventions; see `references/conventional-commits.md` only when applicable.

## CI and review

- Query PR checks and workflow runs for the exact published full SHA. Missing, pending, failed, or unverifiable required checks block merge. Registration can lag: retry for a bounded interval, then report unresolved rather than treating no runs as success.
- Inspect all failed jobs and whether they reached tests. Use `references/ci-troubleshooting.md`; do not broaden permissions, alter assertions, or update dependencies merely because a job failed.
- Obtain one independent static review of the exact committed diff. Parent verifies findings and runs validation. Fixes require implementation authority; changes to head invalidate affected review/check evidence.
- Review comments are evidence, not orders. Resolve evidence-backed blockers; document disagreements without silently dismissing gates.

## Merge and cleanup

Immediately before an authorized merge, verify repository identity, current head, base/upstream compatibility, required CI, and absence of unresolved review blockers for that head. Use the repository's allowed merge strategy and a head-matching guard such as `gh pr merge NUMBER --repo OWNER/REPO --match-head-commit SHA`; specify the permitted strategy rather than relying on defaults. Do not use admin/bypass flags.

Read back the merged state, merge commit, and target branch. A queued auto-merge or successful request is not proof of merge. Update the local base only when doing so preserves local work. Delete only task-owned branches/worktrees after successful delivery and explicit cleanup authority or applicable governing policy; never force-delete shared/pre-existing resources.

Report PR URL, exact delivered head, checks/review status, merge state, and any blocker. Do not claim deployment unless separately authorized and verified.
