# config/windows/Powershell/Microsoft.PowerShell_profile.ps1 startup behavior.

$script:ProfileFile = Join-Path $script:RepoDir 'config/windows/Powershell/Microsoft.PowerShell_profile.ps1'

function test_profile_restores_complete_after_jj_success_and_failure {
    foreach ($throws in $false, $true) {
        $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:PATH = ''
`$env:COMPLETE = 'keep'
function Set-PSReadLineOption { throw 'PSReadLine unsupported' }
function jj { $(if ($throws) { "throw 'completion failed'" } else { "''" }) }
try { . '$script:ProfileFile' } catch { }
if (`$env:COMPLETE -ne 'keep') { throw "COMPLETE leaked: `$env:COMPLETE" }
'complete-restored'
"@
        $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
        Assert-Contains $out 'complete-restored'
    }
}

function test_profile_keeps_managed_pi_ahead_of_fnm_shims {
    $localAppData = Join-Path ([IO.Path]::GetTempPath()) 'dotfile-profile-test-local'
    $managedPi = Join-Path $localAppData 'dotfiles\pi\bin'
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:LOCALAPPDATA = '$localAppData'
`$env:PATH = ''
`$env:Path = 'C:\Windows\System32'
function Set-PSReadLineOption { throw 'PSReadLine unsupported' }
function fnm { '`$env:Path = ''C:\fnm;'' + `$env:Path' }
. '$script:ProfileFile'
(`$env:Path -split ';')[0]
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out $managedPi
}

function test_profile_tab_opens_completion_menu {
    $localAppData = Join-Path ([IO.Path]::GetTempPath()) 'dotfile-profile-test-local'
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:LOCALAPPDATA = '$localAppData'
`$env:PATH = ''
function Set-PSReadLineOption { }
function Set-PSReadLineKeyHandler { param(`$Key, `$Function) "`$Key|`$Function" }
. '$script:ProfileFile'
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out 'Tab|MenuComplete'
}

function test_profile_does_not_autostart_psmux {
    $profile = Get-Content -Raw $script:ProfileFile

    Assert-False ($profile -match '(?i)psmux') 'PowerShell should start directly without psmux'
}

function test_profile_loads_when_psreadline_options_are_unsupported {
    $localAppData = Join-Path ([IO.Path]::GetTempPath()) 'dotfile-profile-test-local'
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:LOCALAPPDATA = '$localAppData'
`$env:PATH = ''
function Set-PSReadLineOption { throw 'PSReadLine unsupported' }
. '$script:ProfileFile'
'profile-loaded'
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out 'profile-loaded'
}
