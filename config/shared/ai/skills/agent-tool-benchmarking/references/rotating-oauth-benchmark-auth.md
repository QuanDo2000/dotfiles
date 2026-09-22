# Rotating OAuth credentials in serial benchmarks

Use this when a CLI benchmark isolates `CODEX_HOME` or an equivalent agent root per cell while authenticating through OAuth.

## Failure mode

Some providers rotate refresh tokens. If every cell copies the same live credential, a cell may refresh successfully in its private home and consume the source refresh token. Deleting that home then makes the next copy stale. A local `login status` command can still report “logged in” because it checks credential presence rather than a real provider exchange.

## Preflight

1. Prefer a dedicated benchmark credential.
2. Otherwise obtain explicit approval for the exact live credential source, copy method, retention, cleanup, and spend ceiling.
3. Verify reauthentication only by a user-completed login plus metadata change and a minimal approved provider probe; never inspect credential bytes.
4. Record the live file's mode, size, mtime, and inode before the run. Preserve all four throughout execution.
5. Confirm whether refresh tokens rotate before choosing per-cell copies.

## Safe chained transport

For rotating OAuth and a long uninterrupted serial matrix:

- Obtain a separate exact approval for one run-scoped credential chain.
- Create a mode-0700 chain directory and mode-0600 credential file by byte-for-byte filesystem copy.
- At each cell start, copy the chain credential into the isolated cell home.
- After the client settles, copy the possibly refreshed cell credential to a mode-0600 temporary file in the chain directory, then atomically rename it over the chain credential.
- Never read, parse, print, hash, diff, archive, or checksum either credential.
- Ignore the credential when preserving cell artifacts.
- Delete the cell home after every cell and the chain on success, handled failure, cancellation, or budget stop. Verify cleanup by existence only.
- Keep the live source unchanged; the chain is transport shared by both benchmark variants, never an A/B difference.

A hard kill may bypass `finally`; add a startup stale-chain rejection or cleanup guard, and verify absence before any resume.

## Invalid attempt recovery

On 401/refresh failure:

1. Stop the matrix immediately.
2. Preserve the complete attempt under `excluded/` with provenance.
3. Parse any emitted usage; count it against the inclusive ceiling, using zero only when telemetry proves provider work never began.
4. Verify worktree and credential cleanup.
5. Require user reauthentication and a fresh exact transport approval.
6. Retry the same canonical cell from a fresh session; never resume its partial patch.
7. Regenerate summaries and checksums after replacement.
