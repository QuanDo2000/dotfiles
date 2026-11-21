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

Use the governing implementation, delivery, signing, and merge policy. This adapter does not expand authorization: research/review remains read-only; authorized implementation may carry automatic task-branch delivery under that policy. Explicit no-commit/no-push restrictions win. Unattended merge follows the governing repository allowlist; explicit exceptions follow the governing policy’s scoped authorization and named-risk rule. Verify repository identity rather than relying on the owner name.

For `github.com/QuanDo2000/dotfiles`, use the governing signed fast-forward workflow by default. Use this recipe only when PR delivery is in scope.

## Prepare and implement

1. Verify the checkout, remote identity, default/base branch, current full SHA, and staged/unstaged/untracked state. Check for an existing task branch/PR before creating duplicates. Distinguish forks from the intended repository.
2. Default to a task branch/worktree or native JJ workspace. For Git worktrees, prefer the main project’s ignored `.worktrees/<task>` directory. Preserve unrelated work and follow governing policy for exceptions to isolation or delivery defaults.
3. Name observable behavior and credible failures, then use the matching test/debug workflow. Run focused checks on the final candidate by default and follow applicable repository requirements. Label any accepted gaps; static review and CI do not prove unchecked behavior.
4. Reinspect the diff after tests/hooks. Prefer staging explicit task paths or reviewed hunks. Inspect the staged diff before committing. Preserve required signing. Diagnose effective backend and key configuration, access to the intended key, and any unlock requirement before asking the user to intervene. Hold signed delivery if signing or cryptographic verification remains unavailable; do not fall back to unsigned commits.

## Publish the task branch

- Fetch and compare upstream before push. Integrate remote advances without overwriting either side and defer ambiguous conflicts by default. Rerun affected checks after integration.
- Default to a non-forced push of the reviewed commits to the verified task branch. For an explicitly authorized push exception, follow the governing source-SHA and destination-ref conditions, signing, and branch protections. Read back the published full SHA and compare it with the intended candidate.
- Inspect existing PRs for the exact head/base before creation. Use `gh pr create --repo OWNER/REPO --base BASE --head BRANCH --title TITLE --body-file FILE`; for a fork, resolve the correct owner-qualified head explicitly.
- Keep the body to problem, scoped change, actual verification, unverified coverage, and relevant risk/rollback. Templates under `templates/` are optional structure, not claims that checks passed. Follow repository title conventions; see `references/conventional-commits.md` only when applicable.

## CI and review

- Query PR checks and workflow runs for the exact published full SHA. Registration can lag: retry for a bounded interval, then report missing, pending, failed, or unverifiable evidence as such. Distinguish externally required checks from discretionary delivery gates.
- Inspect all failed jobs and whether they reached tests. Use `references/ci-troubleshooting.md`; do not broaden permissions, alter assertions, or update dependencies merely because a job failed.
- Follow governing policy for review depth and unattended merge. Parent verifies findings and runs validation. Fixes require implementation authority; changes to head invalidate affected review/check evidence.
- Review comments are evidence, not orders. Resolve material findings by default; report any explicitly accepted unresolved finding without calling it fixed or approved.

## Merge and cleanup

Immediately before merging, verify repository identity, target, current head, upstream compatibility, and the status of review and checks for that head. Follow governing merge defaults, scoped exceptions, and independently imposed requirements. For ordinary merges, use `gh pr merge NUMBER --repo OWNER/REPO --merge --match-head-commit SHA` when the governing default is allowed. Any alternative must meet the governing non-squash and signature-preservation requirements. A head-only guard does not bind the target for an exception. Do not use admin/bypass flags.

Read back the merged state, merge commit, and target branch, and verify the original signed commits and any new merge commit under the governing policy. A queued auto-merge or successful request is not proof of merge. Update the local base only when doing so preserves local work. Apply the governing post-delivery cleanup defaults or the separate rules for explicit removal of named resources, including abandoned work. Preserve unrelated or shared work.

Report PR URL, exact delivered head, checks/review status, merge state, and any blocker. Do not claim deployment unless separately authorized and verified.
