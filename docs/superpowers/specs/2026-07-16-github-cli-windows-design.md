# GitHub CLI on Windows

## Design

Add `GitHub.cli` to `Get-WingetPackages` and `gh` to `Get-RequiredCommands`.
The existing Windows install, update, and doctor paths will then manage and
verify GitHub CLI without a special installer.

## Testing

Extend the existing package-manifest test to require both entries. Run that
test red before editing the manifests, then run the full PowerShell suite and
one real `dotfile` setup followed by `dotfile doctor`.
