# Standalone Linux root-owned system files from dotfiles

Use this pattern when Home Manager runs on a non-NixOS distribution but a machine role also needs root-owned files under `/etc` or `/usr/local`.

## Ownership boundary

- Home Manager owns user configuration only. Do not put `sudo` inside Home Manager activation.
- Keep the root-owned script, service/timer units, and installer together under a host-role directory such as `config/<role>/<feature>/`.
- Invoke the installer only through the repository's existing role router, after successful user-profile activation.
- Scope it to setup and full updates for that role. Exclude generic profiles, other operating systems, and narrow updates such as AI-only refreshes.

## Minimal installer

1. Resolve its source directory relative to `BASH_SOURCE`; never depend on a temporary task directory.
2. Require root for the live `/` target.
3. Validate tracked scripts before publication (`bash -n`; add domain checks where available).
4. Stage each destination beside its final path and publish with same-filesystem `mv` so systemd never reads a partially written file.
5. Install scripts as root-owned `0700` when their contents expose service topology or privileged operations; install units as root-owned `0644`.
6. Run `systemd-analyze verify`, then `daemon-reload`, the feature's non-destructive preflight, and `enable --now` for the timer.
7. Do not force an expensive backup or maintenance job on every dotfiles update. Enabling the timer plus preflight is enough; run the workload separately only when explicitly required.

## Test seam

Support a sandbox root such as `FEATURE_ROOT=/tmp/test-root` and an explicit `FEATURE_SKIP_SYSTEMD=true` mode. This permits an unprivileged regression test to assert:

- exact destination paths;
- byte equality with tracked source;
- executable/non-executable modes;
- no writes to the real host.

Add a flow test proving role activation occurs before the root installer. Add integration coverage proving full role updates invoke it and narrow updates do not.

## Verification

- Run the repository-native full checks, ShellCheck, Bash syntax checks, and Nix evaluation/builds.
- Verify deployed unit files byte-match tracked units.
- Verify the timer is enabled and active, and inspect the last service `Result` and `ExecMainStatus`.
- A non-root `systemd-analyze verify` can report a root-owned mode-`0700` `ExecStart` as inaccessible; perform the authoritative live-unit verification in the root installer rather than weakening file permissions.
- Preserve the user's worktree state and leave changes uncommitted/unpushed unless requested.
