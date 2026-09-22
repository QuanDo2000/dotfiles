# Home Manager and Nix Verification Pitfalls

## Git-backed flakes omit untracked inputs

A dirty Git flake includes modified tracked files but excludes untracked files. A derivation may therefore evaluate from `path:/repo` yet fail from `/repo#target` or `git+file:///repo` when it references a newly generated lock/source file.

Typical evidence:

```text
error: getting status of '/nix/store/...-source/packages/generated-lock.json': No such file or directory
```

Diagnosis:

1. Compare `git status --short` with every path referenced by the failing derivation.
2. Confirm the missing file exists in the worktree but is absent from `git ls-files`.
3. Evaluate with `path:/absolute/repo#target` only to prove untracked-input filtering is the boundary.

Durable resolution: make the generated input a tracked part of the feature. Do not permanently route normal updates through `path:` merely to hide missing repository inputs. Never stage unrelated user changes.

## MIME declarations can point to absent applications

Home Manager can generate a correct `mimeapps.list` while `xdg-mime query default` falls back or returns nothing because the declared desktop application is not installed.

Verify all three layers:

```bash
xdg-mime query default inode/directory
command -v thunar
# confirm thunar.desktop exists in an XDG applications directory
```

The root fix is to include the promised handler package in the same platform package declaration as its MIME default. Add a regression assertion for both the package and MIME declaration, apply Home Manager, then query runtime behavior again.

## Session-aware service interpretation

Home Manager desktop units can be correctly installed yet inactive when `graphical-session.target` is inactive. Check:

- `systemctl --user --failed`
- `systemctl --user is-active graphical-session.target`
- unit socket activation, such as `pipewire-pulse.socket`
- portal/audio client behavior (`pactl info`, portal status)

An inactive desktop unit without a graphical session is not a failed update. Do not start the session solely for verification; report the GUI-only runtime check as deferred.

## Worktree snapshots prevent accidental overwrite

Capture `git status --short --branch` before tests and again after each activation/check phase. If unrelated files appear or change during the run, assume concurrent/user work until proven otherwise. Preserve it; do not reset based only on the earlier clean snapshot.
