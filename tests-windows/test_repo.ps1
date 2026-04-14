# EnsureRepo / UpdateRepo with git mocked.

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

function test_ensurerepo_skips_clone_when_dir_exists {
    New-Item -ItemType Directory -Path $script:DotfilesDir | Out-Null

    EnsureRepo

    Assert-Equals 0 $global:GitCalls.Count
}

function test_ensurerepo_clones_when_dir_missing {
    Assert-False (Test-Path $script:DotfilesDir) 'precondition: repo dir should not exist'

    EnsureRepo

    Assert-Equals 1 $global:GitCalls.Count
    Assert-Equals 'clone' $global:GitCalls[0][0]
}

function test_updaterepo_skips_git_in_dry_mode {
    New-Item -ItemType Directory -Path $script:DotfilesDir | Out-Null
    $script:Dry = $true

    UpdateRepo

    Assert-Equals 0 $global:GitCalls.Count
}

function test_updaterepo_calls_pull_when_not_dry {
    New-Item -ItemType Directory -Path $script:DotfilesDir | Out-Null
    $script:Dry = $false

    UpdateRepo

    Assert-Equals 1 $global:GitCalls.Count
    Assert-Equals 'pull' $global:GitCalls[0][0]
    Assert-Contains ($global:GitCalls[0] -join ' ') '--rebase'
    Assert-Contains ($global:GitCalls[0] -join ' ') '--autostash'
}
