# config/windows/Powershell/Microsoft.PowerShell_profile.ps1 startup behavior.

$script:ProfileFile = Join-Path $script:RepoDir 'config/windows/Powershell/Microsoft.PowerShell_profile.ps1'

function test_profile_loads_when_optional_tools_are_missing {
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:PATH = ''
. '$script:ProfileFile'
'profile-loaded'
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out 'profile-loaded'
}
