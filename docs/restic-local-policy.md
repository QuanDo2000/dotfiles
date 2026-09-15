# Machine-local Restic exclusion policy

The Arch-server storage backup uses the managed case-insensitive baseline plus
`~/.config/restic/storage-offsite-local-excludes`, a user-owned, case-sensitive
Restic pattern file. Generic Linux, macOS and NixOS profiles do not require this
local storage-backup policy.

Before first Arch-server activation, explicitly prepare and review the local
policy. Write the intended patterns with your editor, or deliberately choose an
empty policy only if no machine-local exclusions are required. For that explicit
empty-policy choice, this non-overwriting command refuses existing files and
symlinks (including dangling symlinks):

```bash
(
  set -eu
  umask 077
  policy="$HOME/.config/restic/storage-offsite-local-excludes"
  mkdir -p "$HOME/.config/restic"
  if [ -e "$policy" ] || [ -L "$policy" ]; then
    printf '%s\n' 'Policy already exists; review it without overwriting.' >&2
    exit 1
  fi
  set -o noclobber
  : > "$policy"
)
```

Do not use empty initialization to repair a lost policy: restore its reviewed
contents from a trusted copy, or explicitly review a new coverage policy first.
Keep machine-specific patterns out of this repository. A symlink to a readable
regular policy file is supported and remains untouched.

Home Manager checks the policy before `writeBoundary`, including during its
dry-run. Missing, unreadable, non-regular and dangling paths abort activation
with remediation instructions; activation never creates or rewrites this file.
An intentionally empty readable file is accepted. Build/evaluation does not
check the live file and does not activate the profile. A router-only dry-run
may only print commands; it is not proof the activation preflight ran.

If the policy disappears after activation, Restic's mandatory `--exclude-file`
argument fails the backup rather than silently dropping the policy. This guard
is not a file-integrity monitor: deliberate edits or truncation of a readable
file require the owner's review, and a preflight cannot prevent later changes.

After reviewing the policy and building the intended Arch-server profile,
deploy separately through the repository's role-aware package/setup router.
Do not switch a generic Linux profile on an initialized storage-backup host.
