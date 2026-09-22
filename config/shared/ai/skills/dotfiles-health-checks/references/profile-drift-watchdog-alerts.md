# Diagnosing watchdog alerts caused by Home Manager profile drift

Use when a watchdog cannot verify a backup or managed service after a Home Manager activation, especially when the feature is enabled only for one machine role.

## Diagnose from the alert inward

1. Read the exact delivered watchdog output.
2. Run the watchdog manually with tracing or temporarily restore stderr around the failing probe. A generic `Unable to verify...` message may hide exit `127`, authentication failure, repository failure, or stale data.
3. Check each boundary separately:
   - binary: `command -v restic` and `restic version`
   - credentials: test readability without printing contents
   - repository: run the same read-only snapshot query with stderr visible
   - units: inspect service/timer load, enabled, and active states
   - deployed profile: identify the active Home Manager generation
4. Check backup history independently. A recent snapshot proves the last run succeeded; it does **not** prove the timer or tool still exists for the next run.

## Prove profile drift without activating anything

Compare the deployed generation to the expected machine-role target:

```bash
current="$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")"
expected="$(nix build --no-link --print-out-paths \
  "path:$repo#homeConfigurations.\"$USER@$role\".activationPackage")"
[[ "$current" == "$expected" ]]
```

Evaluate both generic and role-specific profiles when needed:

```bash
nix eval --json \
  "path:$repo#homeConfigurations.\"$USER@$role\".config.home.packages" \
  --apply 'xs: builtins.map (x: x.name) xs'
```

Also query the expected unit option or inspect the built generation. This distinguishes a broken declaration from a correct declaration that was never deployed.

## Root-cause pattern

A generic profile can intentionally omit a host-scoped package and its timers. Activating that profile on the server removes both, while an hourly watchdog begins reporting that it cannot verify the repository. The alert is actionable even if the last snapshot is fresh: future scheduled backups are no longer guaranteed.

Do not “fix” this by adding a one-off binary, widening the watchdog `PATH`, or suppressing the alert. Restore the intended machine-role profile through the normal project activation path.

## Safe repair and verification

1. Snapshot the dirty worktree and build the role target first.
2. Activate the expected role target with the repository-native command; use direct `home-manager switch --flake "path:$repo#$USER@$role"` only when that is the established fallback.
3. Verify all layers:
   - active generation equals the built role generation
   - managed binary resolves and runs
   - read-only latest-snapshot query succeeds and is within policy
   - backup and maintenance timers are enabled and active, with plausible next runs
   - watchdog self-test passes
   - live watchdog output is empty when healthy
   - scheduler-triggered watchdog run succeeds silently
4. Report whether data was safe **and** whether future scheduling was restored.
5. Check recurrence at the declarative entry point before claiming the dotfiles were fixed:
   - trace every normal activation command (`all`, package install, full update, scoped update, doctor) to the selected Home Manager target
   - run the focused routing regression tests and confirm the server role is selected
   - if the repository already routes normal commands correctly, do not invent a source patch; identify the drift as an out-of-band generic-profile activation and state that normal project commands will preserve the repaired role
   - warn that a direct `home-manager switch` to the generic profile can still remove role-scoped packages and units

## Guard against direct wrong-profile activation

When recurrence must be blocked, guard the real command path rather than only the repository router:

1. Put a high-priority `home-manager` wrapper package in the standalone Home Manager profile. A wrapper under `~/.local/bin` may not work because `~/.nix-profile/bin` can appear earlier in agent and service `PATH`s.
2. On hosts carrying an existing role marker (for example, `~/.local/state/dotfiles/storage-offsite-backup-initialized`), allow `switch` only when one argument selects the required role target. Delegate all other subcommands to the pinned underlying Home Manager binary by absolute store path.
3. Add an activation DAG check before `writeBoundary` as defense in depth for callers that bypass the wrapper with `nix run` or an absolute store path. This prevents managed links and units from changing, but it is not sufficient alone: Home Manager advances its generation pointer before the activation script runs.
4. Verify both paths: the wrong direct command exits nonzero without changing the generation pointer, while the correct role switch succeeds; then re-check role timers and watchdog silence.

## Attribute the activation before assigning blame

1. Correlate the new Home Manager generation timestamp with the alert and known work windows.
2. Agree on bounded sources and a time window before accessing history. Prefer current-session evidence or user-selected exports; do not scan raw session stores automatically. Treat shell history as a lead rather than proof: it may lack timestamps, and another concurrent agent may own the activation.
3. Within the approved sources/window, search for `home-manager switch`, the generic target, or the generation store path. Keep transcript excerpts private and minimal.
4. Recover the exact tool-call arguments from JSONL when normal search output truncates a long line. Confirm attribution with the activation result—for example, the same call reports stopping the role-only timers.
5. If journald, auditd, process accounting, and transcripts do not identify the caller, report the exact caller as unknown. Never turn an un-timestamped history entry into a claim that the user ran it.
6. Agents applying live configuration on a role-scoped host must use the repository-native activation router or derive the role through its shared platform helper. Do not hardcode the generic profile in an ad hoc verification command.

Never print repository passwords, API keys, or credential-file contents.
