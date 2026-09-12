# Reviewer evidence handoffs

Use when a Pi/Codex reviewer is intentionally read-only or lacks shell/Git tools.

## Preflight evidence packet

Before dispatch, the writer/parent should create or collect:

- repository/worktree path, base ref, branch, and intended side-effect boundary;
- `git status --short` with unrelated runtime artifacts identified;
- changed-file list, including untracked files;
- complete diff against the agreed base, or a durable diff artifact path the reviewer can read;
- deleted-file contents when parity depends on what was removed;
- validation commands and exact results already obtained.

Pass this packet in the initial reviewer prompt. Do not make a restricted reviewer rediscover Git state from packed objects or infer changes from an index.

## Supervisor handoff recovery

If a reviewer requests evidence through intercom:

1. Generate the requested evidence from the writer's worktree.
2. Reply to the existing supervisor request.
3. Wait on or recover the same detached run.
4. Do not launch a replacement while the original run remains recoverable.
5. Treat a workflow timeout separately from a review finding: inspect persisted child output and salvage completed findings before retrying only the missing lane.

Completion means the reviewer received the exact evidence, returned actionable findings or an explicit clean verdict, and the parent independently verified any resulting edits/tests.
