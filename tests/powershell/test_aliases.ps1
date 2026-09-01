# config/windows/Powershell/aliases.ps1 — parity aliases.
# The collision check runs in a child pwsh so the built-in AllScope aliases
# (gc/gp/gl/gm/gcm) are removed at top scope, mirroring how the profile loads it
# — removing them in the runner's child scope wouldn't shadow the parent's copy.

$script:AliasesFile = Join-Path $script:RepoDir 'config/windows/Powershell/aliases.ps1'

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

function test_ssh_uses_conservative_term_only_inside_psmux {
    $probe = @"
function ssh.exe { "inside=`$env:TERM args=`$(`$args -join ',')" }
. '$script:AliasesFile'
if ((Get-Command ssh).CommandType -ne 'Function') {
    'ssh-wrapper-missing'
} else {
    `$env:TERM = 'xterm-256color'
    `$env:PSMUX_ACTIVE = '1'
    ssh quanarch -v
    "after=`$env:TERM"
    Remove-Item Env:\PSMUX_ACTIVE
    ssh nixos
}
"@
    $out = pwsh -NoProfile -Command $probe | Out-String

    Assert-Contains $out 'inside=screen-256color args=quanarch,-v'
    Assert-Contains $out 'after=xterm-256color'
    Assert-Contains $out 'inside=xterm-256color args=nixos'
}
