# Pulling Remote Changes into a Dirty Dotfiles Worktree

## Safe sequence

1. Snapshot `git status --short --branch` and the current diff.
2. Use `git pull --rebase --autostash` when the user explicitly wants the remote update applied while preserving local edits.
3. Always inspect `git status` afterward. Git can fast-forward successfully yet leave conflicts while reapplying the autostash.
4. Compare conflicted files against `HEAD:path`, not just conflict-marker labels. Remote work may already implement the same feature more completely.
5. Keep the remote implementation when it absorbs the local feature; reapply only unique local deltas such as security hardening or tests.
6. Mark conflicts resolved, then reset the index if the user's original edits were unstaged and should remain unstaged.
7. Run targeted tests and a Home Manager build before treating the merge as resolved.
8. Review the new diff relative to updated `HEAD`; it should usually be smaller than the pre-pull diff.
9. Drop the generated autostash only after proving every unique local change is either present in the worktree or absorbed upstream.

## Pitfalls

- A zero exit from `git pull --rebase --autostash` does not prove the autostash reapplied cleanly.
- Do not blindly choose "stashed changes" for overlapping features; this can overwrite newer remote design work.
- Do not leave conflict resolution staged when the user's original work was unstaged unless they asked for staging.
- Do not activate a newly merged Home Manager generation merely to inspect its diff. Build first; activate only when requested or when completing an approved live fix.
