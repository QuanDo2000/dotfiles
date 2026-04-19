# Verify — drives the function end-to-end with mocked lookups. Verify uses
# $env:USERPROFILE (overridden by Initialize-TestEnv) so it operates on the
# temp home; tests still focus on control-flow coverage rather than asserting
# specific file-existence outcomes.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared') -Force | Out-Null
    # Create stub source files so Verify's Compare-Object call never throws on
    # missing sources when the real $HOME happens to contain matching dests.
    'g' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.gitconfig')
    'v' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.vimrc')
    'gv' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\_gvimrc')
    # Verify's informational output flows through Info/Success, which are
    # gated by $script:Quiet. Keep Quiet off so 6>&1 captures the banners the
    # assertions look for.
    $script:Quiet = $false
}

function TestTeardown {
    Clear-CommandMock 'Get-Command'
    Clear-CommandMock 'Get-Module'
    Clear-TestEnv
}

function test_verify_emits_each_verification_phase {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'Verifying installed tools'
    Assert-Contains $output 'Verifying scoop packages'
    Assert-Contains $output 'Verifying PowerShell modules'
    Assert-Contains $output 'Verifying copied files'
    Assert-Contains $output 'Verifying neovim config'
}

function test_verify_reports_issues_when_tools_absent {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    # At least the six tool lookups should come back missing.
    Assert-Contains $output 'not found'
    Assert-Contains $output 'issue'
}

function test_verify_reports_tools_found_when_mocks_return_objects {
    Set-CommandMock 'Get-Command' {
        [pscustomobject]@{ Source = 'C:\fake\tool.exe' }
    }
    Set-CommandMock 'Get-Module' {
        [pscustomobject]@{ Name = 'FakeModule' }
    }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'found'
    Assert-Contains $output 'installed'
}
