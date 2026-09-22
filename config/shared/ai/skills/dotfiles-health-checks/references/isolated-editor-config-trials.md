# Isolated editor-config trials

Use when comparing a candidate Neovim configuration without activating Home Manager or replacing the live config.

## Pattern

Give candidate its own writable XDG roots while copying only candidate configuration. Keep required immutable/Nix-managed helpers linked read-only.

```bash
TRIAL=/tmp/nvim-config-trial
CANDIDATE=/path/to/candidate-worktree

test ! -e "$TRIAL" || { echo "$TRIAL already exists"; return 1; }
mkdir -p "$TRIAL/config"
cp -a "$CANDIDATE/path/to/nvim" "$TRIAL/config/nvim"

trialvim() {
  XDG_CONFIG_HOME="$TRIAL/config" \
  XDG_DATA_HOME="$TRIAL/data" \
  XDG_CACHE_HOME="$TRIAL/cache" \
  XDG_STATE_HOME="$TRIAL/state" \
  nvim "$@"
}
```

Also redirect application-specific writable databases when plugins use paths outside XDG roots. For FFF, isolate `FFF_FRECENCY_DB` and `FFF_HISTORY_DB`. If candidate expects a Nix-managed backend already present in live config, symlink only that backend into candidate config rather than copying or rebuilding it.

Isolating `XDG_DATA_HOME` also hides Home Manager/Nix-installed start packages such as `lazy.nvim` that normally live under `$XDG_DATA_HOME/nvim/site/pack/*/start`. Link each required immutable package into the equivalent trial path before first startup. Do not infer success from process exit alone: Neovim may report startup or Ex-command errors while returning zero.

## Durable launcher

For repeated trials, prefer one executable in `~/.local/bin` over a shell-only function. It should:

1. Create and snapshot candidate config only when trial config is absent.
2. Create isolated writable roots and plugin-specific databases.
3. Refresh symlinks to immutable live/Nix helpers on every invocation.
4. `exec env ... nvim "$@"` so arguments and exit behavior remain transparent.

Because config is a snapshot, candidate worktree changes do not appear until trial root is deliberately removed and rebuilt. State this clearly; never silently overwrite a trial containing user state.

### Refreshing a durable trial

Before saying a launcher is current, compare the candidate config tree with the trial snapshot (`diff -qr`, excluding deliberate helper symlinks) and record the candidate commit. A launcher existing on `PATH` proves only installation, not freshness.

Refresh only with explicit user approval because replacing the trial config is destructive. Preserve the trial's data/cache/state roots so downloaded plugins and manual test state survive; replace only the config snapshot, recreate deliberate helper links, then restore locked plugins and rerun the marker/framework-absence assertions. If the user wants a completely clean bootstrap, remove the entire trial root instead.

`Lazy restore` may rewrite harmless lock metadata such as a repository's default branch while retaining the exact pinned commit. Compare the lockfile after restore: identical commit with branch-only drift is not a plugin upgrade, but keep the candidate worktree untouched and report the drift rather than copying it back automatically.

## Verification

1. Restore candidate's locked plugins inside isolated roots, capturing output and checking both status and decisive error text.
2. Add/use a candidate marker and assert it headlessly.
3. Assert removed framework/plugin is absent rather than relying on appearance.
4. Launch live `nvim` and trial function concurrently.
5. Test only key workflows affected by candidate: picker, grep, explorer, buffers, Git, LSP, formatting, sessions, terminal integration.
6. Use disposable files for formatting/lint tests.

## Cleanup

Exit trial instances, remove only trial root, and unset shell function/variables. No live rollback is needed because no live managed link changed.

## Home Manager boundary

Do not use `home-manager switch` for an isolated trial: it replaces live managed links. Use build/check-only validation first. Activate only after user chooses adoption and normal rollback/generation checks are ready.
