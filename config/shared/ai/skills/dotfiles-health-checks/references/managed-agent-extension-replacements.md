# Managed Agent Extension Replacements

Use this recipe when dotfiles pin and deploy a stateful agent extension and the replacement owns overlapping tools, hooks, or memory authority.

## Cutover

1. Inventory the declarative package/lock, live settings, resolved package manifest, current generation, state directories, and running agent processes. Record the old release ID and generation as rollback handles.
2. Confirm whether the extensions can coexist. Duplicate tool names or singleton providers require a one-for-one settings change; do not install both and hope load order resolves it.
3. Replace the exact pinned dependency and regenerate the lock without running lifecycle scripts. Refresh the closure hash/release ID and every local-release path. A behavioral patch addition/removal also needs a fresh release ID even when dependency versions are unchanged: if the ID is the lock hash, bump the private bundle version and regenerate the lock so existing immutable directories cannot short-circuit installation.
4. Delete extension-specific baggage that no longer has a consumer: native dependency pins, compiler inputs, source patches, installer branches, fixtures, and platform assertions. Keep generic integrity checks.
5. If the new package declares a lifecycle script but deployment always uses `--ignore-scripts`, whitelist only its exact lock entry in pin validation; reject every other scripted package.
6. Preserve the old state directory. Migrate user and durable memory losslessly into the new store, set directory/file modes such as `0700`/`0600`, and do not copy credentials. If automatic context injection truncates large stores, preserve the full file anyway and report the retrieval/injection boundary rather than silently dropping data.
7. Build the package and run focused Unix and cross-platform installer tests before activation. Activate the exact deployed host profile, not a generic profile.

## Provider-Free Verification

- Start a fresh agent in RPC/headless mode, issue a state-only command, and require a clean exit, successful response, and empty stderr. This proves the live extension set loads without spending provider tokens.
- Read back the resolved live manifest and require the selected name/version/release. For a patch-policy change, inspect the deployed entry for the expected source marker; package version alone cannot distinguish patched from upstream behavior.
- Require zero old-extension references in active settings and the active release. Historical releases and preserved stores are rollback assets, not active references.
- Hash migrated state before and after startup; require stability. Verify modes and source-store preservation.
- Verify the registered tool/event surface using a provider-free loader against the tested source. If standalone loading cannot resolve host-provided peer dependencies, hash the deployed entry against the already-tested pinned source and combine that identity check with the successful real host startup; do not call the standalone failure a product defect.
- Check for pre-cutover long-running agent processes. Fresh settings do not rewrite extensions already loaded into an existing process.

## Completion Gates

- focused regression passes
- full repository check passes after the final production edit
- flake/package build passes
- dependency audit is clean or findings are reported
- doctor and failed-unit checks pass
- exact deployed profile is active
- final worktree status and commit state are reported
- rollback store and prior generation remain available

Re-activate after any production deployment or pin-updater change made while fixing tests. A green source suite does not update the live generation.
