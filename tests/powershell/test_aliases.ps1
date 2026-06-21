# config/windows/Powershell/aliases.ps1 — parity aliases.
# The collision check runs in a child pwsh so the built-in AllScope aliases
# (gc/gp/gl/gm/gcm) are removed at top scope, mirroring how the profile loads it
# — removing them in the runner's child scope wouldn't shadow the parent's copy.

$script:AliasesFile = Join-Path $script:RepoDir 'config/windows/Powershell/aliases.ps1'

function test_aliases_file_exists {
    Assert-FileExists $script:AliasesFile
}

function test_collisions_removed_and_functions_win {
    # Dot-source at top scope in a clean pwsh, then report how each name resolves.
    $probe = ". '$script:AliasesFile'; " +
        "'gc=' + (Get-Command gc).CommandType; " +
        "'gl=' + (Get-Command gl).CommandType; " +
        "'ga=' + (Get-Command ga).CommandType"
    $out = pwsh -NoProfile -Command $probe | Out-String
    # If the built-in aliases weren't removed, these would resolve to Alias.
    Assert-Contains $out 'gc=Function'
    Assert-Contains $out 'gl=Function'
    Assert-Contains $out 'ga=Function'
}

function test_codex_calls_executable_not_itself {
    # The body must call the application explicitly, or `codex` recurses forever.
    $probe = ". '$script:AliasesFile'; (Get-Command codex).Definition"
    $out = pwsh -NoProfile -Command $probe | Out-String
    Assert-Contains $out '-p dotfiles'
    Assert-Contains $out 'Get-Command codex -CommandType Application'
}
