# Headless Git Publishing

Use this after a reviewed, tested dotfiles change must be committed and pushed from a noninteractive agent session.

## Publish sequence

1. Snapshot `git status --short --branch`, inspect staged and unstaged stats, run `git diff --check`, and review the actual diff.
2. Stage only intended files. Commit normally with required signing. If GPG needs interactive unlocking, stop the signing attempt and ask the user to unlock through pinentry in their own terminal; never retry unsigned or change signing configuration to evade the gate.
3. Push without force.
4. If rejected because the remote advanced, fetch and inspect `HEAD...origin/BRANCH`. Rebase only after confirming the upstream commit is legitimate and preserving its unique changes.
5. Resolve overlaps at the behavioral level, not by blindly choosing ours/theirs. Keep upstream fixes that remain relevant and remove superseded code/tests rather than leaving dead alternatives.
6. Run focused tests for resolved conflicts, then the repository's full checks on the rebased tree.
7. Push and verify `git status --short --branch` plus matching local/remote commit IDs.

## Signed-commit rebase recovery

A rebase can retain `-S` in sequencer state even when `commit.gpgsign=false` is supplied later. Do not edit `.git/rebase-*` state files: an empty or malformed signing option can be interpreted as a bogus key ID.

When resolved files are staged and `git rebase --continue` needs GPG, preserve the sequencer and signing requirement. Have the user unlock the intended key in their own terminal, then retry `git rebase --continue` normally. Do not manufacture an unsigned replacement commit. Re-run affected checks on the final rebased tree and verify its signature before publication.

For attended GPG unlocking/testing, give the user this sequence with the intended public fingerprint substituted:

```sh
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye
printf 'Signing availability check\n' | gpg --local-user <fingerprint> --armor --detach-sign
```

The passphrase belongs only in pinentry. A successful signature establishes that key's current signing availability; a public-key listing alone does not. A missing secret key is a provisioning/token-access issue, not an unlock problem. Keep backend configuration, key availability, and agent unlock state as separate diagnoses.

## Concurrent writers and partial staging

When unrelated work lands in the same dirty files, file-level staging is unsafe:

1. Re-diff after activation and tests; hooks or another writer may have added hunks since the initial snapshot.
2. Construct a minimal patch containing only the reviewed hunks and apply it to the index with `git apply --cached`. Inspect `git diff --cached` and confirm unrelated edits remain unstaged.
3. Commit the intended patch, then verify that exact commit in a detached worktree so unstaged or later commits cannot make the checks look greener than the published change.
4. Re-read `HEAD`, `origin/BRANCH`, and the graph immediately before pushing. Another writer may have committed or pushed while verification ran.
5. Never push the branch tip merely because it now contains the intended commit. If the tip includes unowned commits, push only the intended commit when it is still a fast-forward; if the remote already advanced to a descendant, verify the intended commit is an ancestor and do not rewrite or duplicate it.
6. CI may exist only for the descendant that reached the remote. Keep exact-commit local evidence, then require successful CI for the remote descendant and report that relationship accurately.

## Pitfalls

- Never force-push over an uninspected remote advance.
- A clean textual rebase does not prove behavioral compatibility.
- Do not claim push success until the remote update and final branch status are both verified.
- Never use unsigned fallback to satisfy a signed-delivery task; report the signing blocker and preserve the candidate.
