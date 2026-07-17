# config/windows/Powershell/Microsoft.PowerShell_profile.ps1 startup behavior.

$script:ProfileFile = Join-Path $script:RepoDir 'config/windows/Powershell/Microsoft.PowerShell_profile.ps1'

function test_profile_loads_when_psreadline_options_are_unsupported {
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:PATH = ''
function Set-PSReadLineOption { throw 'PSReadLine unsupported' }
. '$script:ProfileFile'
'profile-loaded'
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out 'profile-loaded'
}
