# Stateful Service Path Migrations

Use this when declarative dotfiles manage links/services for data that is also registered in an application's runtime state.

## Sequence

1. Trace every old-path reference: Home Manager targets, service wrappers, setup scripts, tests, docs, application registries, and credential/config directories.
2. Update declarations and tests; run targeted tests and build the generation, but do not activate if activation would create the destination before the move.
3. Confirm the service is healthy and fully synchronized, then stop it.
4. Require source present and destination absent. Rename on the same filesystem and verify the directory device/inode is unchanged. Remove the old parent only when empty.
5. Update application registration separately. A filesystem rename does not update path-keyed runtime state.
6. Activate the declarative generation, restart the service, and verify its live command/logs use the new path.
7. Verify old path absent, destination inventory intact, and no broken managed symlinks.

## Credential-bearing registrations

Runtime registration files can mix path fields with tokens or encryption keys. Never print or broadly diff the file just to change a path. Parse it, change only the path key, preserve permissions, write a same-directory temporary file, and atomically replace the original. Output only confirmation and old/new paths.

## Obsidian Headless example

`obsidian-headless` keeps path-specific registrations under `~/.config/obsidian-headless/sync/*/config.json`. After moving a vault, update only `vaultPath`; otherwise `ob sync-status --path NEW_PATH` reports no configuration even though all vault files moved correctly.

Verification:

- `ob sync-status --path NEW_PATH` succeeds
- systemd `ExecStart` names `NEW_PATH`
- recent journal reaches `Fully synced`
- Home Manager-managed `.obsidian` links are valid

Build Home Manager before the move, rename before activation, then activate. Activating first can populate the destination and prevent the atomic rename. If desktop Obsidian has a separate vault registry, reopen/add the new folder through the app when practical rather than guessing its schema.

## Rollback

On failure, keep the service stopped. Restore the runtime registration path and rename the directory back before restarting. Avoid fresh setup/relink commands until existing registration state is understood; they can create conflicts or require encryption credentials.
