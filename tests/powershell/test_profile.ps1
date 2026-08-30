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

function test_profile_psmux_attach_falls_back_to_main_session {
    $localAppData = Join-Path ([IO.Path]::GetTempPath()) 'dotfile-profile-test-local'
    $probe = @"
`$ErrorActionPreference = 'Stop'
`$env:LOCALAPPDATA = '$localAppData'
`$env:PATH = ''
`$script:PsmuxCalls = @()
function Set-PSReadLineOption { throw 'PSReadLine unsupported' }
function psmux {
    `$script:PsmuxCalls += (`$args -join ' ')
    if (`$args[0] -eq 'attach') { `$global:LASTEXITCODE = 1 } else { `$global:LASTEXITCODE = 0 }
}
. '$script:ProfileFile'
Enter-PsmuxMainSession
`$script:PsmuxCalls -join '|'
"@
    $out = pwsh -NoProfile -Command $probe 2>&1 | Out-String
    Assert-Contains $out 'attach -t main|new-session -s main'
}

function test_profile_psmux_autostart_is_guarded {
    $profile = Get-Content -Raw $script:ProfileFile

    Assert-Contains $profile '$env:TMUX'
    Assert-Contains $profile '$env:NO_TMUX'
    Assert-Contains $profile '[Console]::IsInputRedirected'
    Assert-Contains $profile "'vscode'"
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
