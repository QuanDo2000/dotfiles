# Nix ownership and cross-platform PowerShell checks

## Ownership boundary

Prefer this split:

- **Nix/Home Manager owns:** package versions, executable closures, generated wrappers, declarative config baselines, and activation commands.
- **Applications own:** caches, databases, indexes, history/frecency stores, and live config files that the application must rewrite.
- **Pinned runtime managers may own:** plugin trees whose application expects to update in place. Do not add a second Nix owner unless drift or reproducibility failures justify replacing that model.

A Home Manager wrapper should close over Nix paths rather than ambient `PATH`:

```nix
home.file.".local/bin/example-agent" = {
  text = ''
    #!${pkgs.runtimeShell}
    exec "${pkgs.example}/bin/example" "$@"
  '';
  executable = true;
};
```

Activation hooks should likewise invoke `"${pkgs.example}/bin/example"`. Mutable settings written by that command can remain outside the store.

## Verification

1. Evaluate all declared systems: `nix flake check --no-build --all-systems`.
2. Build affected packages and the native activation package.
3. Apply through the repository's normal Home Manager or nix-darwin command.
4. Verify `readlink -f` for managed files and inspect generated wrappers: the shebang and executable should resolve into `/nix/store`.
5. Run the wrapper's health/version command and inspect application-owned mutable settings separately.
6. Cross-platform evaluation is not runtime verification: report macOS as evaluation-only when working from Linux.

## Portable hosted-runner checks

A script can be Linux-only in deployment but cross-platform in validation. If macOS CI invokes its `--self-test`, that path must avoid GNU-only flags such as `realpath -m`. Prefer a small lexical canonical-path check when the input may not exist locally:

- require an absolute path;
- reject trailing `/`, `//`, `/./`, and `/../` segments;
- then enforce the explicit allowed-root list;
- keep traversal, duplicate-separator, and dot-segment cases in the script's self-test.

When a shared JSON/config invariant changes, search both Bash and PowerShell tests for the old model, role, limit, or alias. Update mirrored expectations in the same commit; passing the native suite alone is insufficient.

## Portable PowerShell fixtures

PowerShell tests for Windows dotfiles often run under `pwsh` on Unix. Windows-only environment variables may be null there, causing unrelated `Join-Path -Path $null` failures. Save, set, and restore them in the shared fixture:

```powershell
$script:_OrigAppData = $env:APPDATA
$script:_OrigLocalAppData = $env:LOCALAPPDATA
$env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'

# teardown
if ($null -eq $script:_OrigAppData) {
    Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
} else {
    $env:APPDATA = $script:_OrigAppData
}
```

Use `Join-Path` in production and assertions. Literal `\` comparisons can pass on Windows while failing under cross-platform `pwsh` for separator reasons rather than behavior.
