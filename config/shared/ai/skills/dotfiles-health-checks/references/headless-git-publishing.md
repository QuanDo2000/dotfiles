# Headless Git Publishing

Use this to commit and push an authorized dotfiles change from a noninteractive agent session. Apply governing delivery defaults and scoped exceptions; a discretionary check that did not run is not a pass.

## Publish sequence

1. Snapshot `git status --short --branch`, inspect staged and unstaged stats, run `git diff --check`, and review the actual diff.
2. Stage only intended files after applying the governing review and verification policy. Commit normally with required signing. SSH is the default: if the intended matching private key is unavailable or locked in the agent, stop and ask the user to restore/unlock that existing identity in their own terminal. Only an explicitly configured OpenPGP backend calls for pinentry. Never retry unsigned or change signing configuration to evade the gate.
3. Verify both fetch and push resolve to `github.com/QuanDo2000/dotfiles`; the usual transport is `git@github.com:QuanDo2000/dotfiles.git`. Fetch and compare `origin/main` and the remote task branch if it exists. Before rebasing, verify advances can be integrated without losing either side's work. Defer ambiguous conflicts by default; resolve overlaps without blindly choosing ours/theirs.
4. Refresh affected review and checks after integration and follow applicable repository requirements. Verify the signature and pin the exact candidate SHA for publication.
5. Default to pushing that scoped signed candidate to the verified task branch without force. Use the governing rule for explicitly authorized push exceptions and honor branch protections. On remote advancement, fetch and reassess before retrying. Read back the remote full SHA and match it to the candidate.
6. Use `github-pr-workflow` for PR delivery, exact-head verification, and merge under the governing policy. Do not use admin bypass.

## Signed-commit rebase recovery

A rebase can retain `-S` in sequencer state even when `commit.gpgsign=false` is supplied later. Do not edit `.git/rebase-*` state files: an empty or malformed signing option can be interpreted as a bogus key ID.

When resolved files are staged and `git rebase --continue` needs signing, preserve the sequencer and signing requirement. Have the user unlock the intended key in their own terminal, then retry `git rebase --continue` normally. Do not manufacture an unsigned replacement commit. Re-run affected checks on the final rebased tree and verify its signature before publication.

## Backend configuration and optional OpenPGP override

Shared Git and Home Manager default to `gpg.format = ssh`, `user.signingkey = ~/.ssh/id_ed25519.pub`, and signed commits/tags. Git expands this public path relative to the user's home; it is not private-key provisioning. `~/.gitconfig.local` is included after managed settings (and Windows settings), so it can override them; repository config wins over user config. Inspect effective values and origins before diagnosis. JJ independently defaults to SSH, the same public path, and behavior `own`; native user `conf.d/*.toml` files override `config.toml`, then repository config wins. Preserve machine-local overrides such as `keep`.

For an explicitly user-chosen OpenPGP override, the user may put `[gpg] format = openpgp` and `[user] signingkey = <intended-existing-fingerprint>` in `~/.gitconfig.local` (as normal multiline Git config sections). Set `gpg.program` there only if a platform-specific executable is needed. For JJ, use a native user `conf.d` TOML file or repository config with `[signing]`, `backend = "gpg"`, and `key = "<intended-existing-fingerprint>"`; retain the required signing behavior. These are optional procedures, not permission to modify live config or evade signed delivery. Keep unrelated GPG encryption, verification, packages, and agent configuration intact.

For SSH, distinguish a wrong public path/backend from unavailable matching private-key/agent access and locked-agent state. Do not enumerate/select a first identity, create keys, or change authentication. Public config checks prove neither signing availability nor trust: actual Git commit/tag and JJ signatures require separate cryptographic verification with the intended trusted public identity. Missing verification trust configuration is distinct from inability to sign.

Only for an explicitly configured OpenPGP backend, give the user this attended unlocking/testing sequence with the intended public fingerprint substituted:

```sh
export GPG_TTY="$(tty)"
gpg-connect-agent updatestartuptty /bye
printf 'Signing availability check\n' | gpg --local-user <fingerprint> --armor --detach-sign
```

The passphrase belongs only in pinentry. A successful signature establishes that key's current signing availability; a public-key listing alone does not. A missing secret key is a provisioning/token-access issue, not an unlock problem. Keep backend configuration, key availability, and agent unlock state as separate diagnoses.

## Scoped SSH signature verification

If signing succeeded but `git verify-commit` reports a missing `gpg.ssh.allowedSignersFile`, preserve the commit and signing configuration. Supply an existing, explicitly trusted verification file for this invocation only:

```sh
git -c gpg.ssh.allowedSignersFile=/path/to/independently-trusted-allowed-signers \
  verify-commit <exact-commit-sha>
```

An artifact-local allowed-signers file is valid; entries use `<trusted-principal> <key-type> <public-key>` syntax. Establish the principal/public-key binding from an independently trusted identity source before creating or using it. Do not obtain trust from the unverified commit, pick the first agent key, or assume an arbitrary configured signing key is trusted. Success proves cryptographic validity against that selected trust file, not broader identity ownership. Retain the exact SHA, result and trust-source rationale in task evidence. Missing trust is not signing failure: do not change machine-wide verification trust, distribute a machine-specific key, disable signing, or claim verification without a successful check. If independent trust is unavailable, report that boundary rather than manufacturing it.

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
