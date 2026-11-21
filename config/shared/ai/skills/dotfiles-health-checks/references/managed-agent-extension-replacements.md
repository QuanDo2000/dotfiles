# Managed Agent Extension Replacements

Use this recipe when dotfiles pin and deploy a stateful agent extension and the replacement owns overlapping tools, hooks, or memory authority.

## Prepare the candidate

1. Inventory the declarative package and lock. For an authorized live cutover, also inspect live settings, the resolved package manifest, generation, state directories, and running agents. Record the old release ID and generation as rollback handles.
2. Confirm whether the extensions can coexist. Duplicate tool names or singleton providers require a one-for-one settings change; do not install both and hope load order resolves it.
3. Replace the exact pinned dependency and regenerate the lock without running lifecycle scripts. Refresh the closure hash/release ID and every local-release path. A behavioral patch addition/removal also needs a fresh release ID even when dependency versions are unchanged: if the ID is the lock hash, bump the private bundle version and regenerate the lock so existing immutable directories cannot short-circuit installation.
4. Delete extension-specific baggage that no longer has a consumer: native dependency pins, compiler inputs, source patches, installer branches, fixtures, and platform assertions. Keep generic integrity checks.
5. If the new package declares a lifecycle script but deployment always uses `--ignore-scripts`, whitelist only its exact lock entry in pin validation; reject every other scripted package.

## Source verification

Build the candidate and choose affected regression, installer, and dependency checks under the governing verification policy. Report coverage and any deferred checks, including cross-platform coverage for a host-only trial. A source-only task does not require live acceptance.

## Authorized live cutover and acceptance

Preserve the old state directory and a usable rollback generation. Migrate user and durable memory losslessly into the new store, set directory/file modes such as `0700`/`0600`, and do not copy credentials. If automatic context injection truncates large stores, preserve the full file and report the retrieval boundary. Activate the exact deployed host profile, not a generic profile.

Check the affected live behavior without spending provider tokens when possible:

- Start a fresh agent in RPC/headless mode and issue a state-only command. Confirm successful exit and response and inspect stderr for startup or extension errors, which can occur even on exit zero. Record benign warnings without failing the check solely because stderr is nonempty.
- Read back the resolved live manifest and require the selected name/version/release. For a patch-policy change, inspect the deployed entry for the expected source marker; package version alone cannot distinguish patched from upstream behavior.
- Require zero old-extension references in active settings and the active release. Historical releases and preserved stores are rollback assets, not active references.
- Hash migrated state before and after startup; require stability. Verify modes and source-store preservation.
- Verify the registered tool/event surface using a provider-free loader against the tested source. If standalone loading cannot resolve host-provided peer dependencies, hash the deployed entry against the already-tested pinned source and combine that identity check with the successful real host startup; do not call the standalone failure a product defect.
- Check for pre-cutover long-running agent processes. Fresh settings do not rewrite extensions already loaded into an existing process.

Use doctor or failed-unit checks when relevant to the affected host operation. Re-activate only if an authorized deployment needs to replace the currently deployed artifact or effective configuration. Report source verification and worktree state separately from what is deployed, what was checked live, and what rollback remains available. A green source suite does not update the live generation.
