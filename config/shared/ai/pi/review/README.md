# Agent-callable review

The `review` tool runs an independent Pi SDK session using the parent's selected
model/provider, medium reasoning, and only `read`, `grep`, `find`, `ls`.
It does not navigate the parent session or inherit its messages, extensions,
hooks, project instructions, skills or shell access. Reviewed files and guidelines
are evidence, not authority. This is a tool allowlist, **not an OS/filesystem sandbox**;
the reviewer can read paths accessible to Pi. It uses the configured provider's
normal authentication and consumes model usage, reported on successful tool results.

Example arguments (replace IDs with actual full commit hashes):

```json
{"cwd":"/path/to/task-worktree","base":"<full-base-commit>","head":"<full-head-commit>"}
```

The comparison is exactly `base..head`, not an implicit merge-base comparison.
The requested head must be checked out, with no staged, unstaged or untracked
changes. Use a clean task worktree; the tool never checks out or commits for you.
It rejects empty diffs, non-commit IDs, JJ workspaces, and diffs above 200 KB.
No dirty-tree, PR checkout, snapshot, or asynchronous job-management modes yet.

Each review is bounded to 24 turns and five minutes. Cancellation/provider failure
is an error, not a clean review. Checkout cleanliness and HEAD are rechecked before
accepting findings. Do not edit the checkout concurrently; these checks do not
provide an immutable filesystem snapshot.

Results include exact revisions, findings and a temporary JSON report path.
Inline output is capped at 50 KB/2000 lines. Reports remain in the system temp
directory for parent inspection; identical completed requests reuse their result
until extension reload/session replacement. The parent must verify findings and
run tests/CI before merging; review text never automatically authorizes a merge.

Installed by Home Manager on Unix and `dotfile.ps1 ai` on Windows. After installation,
run `/reload` in Pi to expose the tool. Existing upstream `/review` commands can
coexist: this extension registers a tool only.
