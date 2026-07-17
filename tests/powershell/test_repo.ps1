# UpdateRepo with git mocked.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $global:GitCalls = [System.Collections.Generic.List[string[]]]::new()
    Set-CommandMock 'git' {
        $global:GitCalls.Add($args)
        $global:LASTEXITCODE = 0
    }
    $script:Quiet = $true
}

function TestTeardown {
    Clear-CommandMock 'git'
    Remove-Variable -Name 'GitCalls' -Scope Global -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function test_updaterepo_skips_git_in_dry_mode {
    $script:Dry = $true

    UpdateRepo

    Assert-Equals 0 $global:GitCalls.Count
}

function test_updaterepo_calls_pull_when_not_dry {
    $script:Dry = $false

    UpdateRepo

    Assert-Equals 1 $global:GitCalls.Count
    $args = $global:GitCalls[0] -join ' '
    Assert-Contains $args "-C $script:DotfilesDir pull"
    Assert-Contains $args '--rebase'
    Assert-Contains $args '--autostash'
}
