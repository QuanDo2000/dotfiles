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

function test_ensurerepo_skips_clone_when_checkout_exists {
    New-Item -ItemType Directory -Path $script:DotfilesDir | Out-Null
    'script' | Set-Content (Join-Path $script:DotfilesDir 'dotfile.ps1')

    EnsureRepo

    Assert-Equals 0 $global:GitCalls.Count
}

function test_ensurerepo_clones_when_target_missing {
    Assert-False (Test-Path $script:DotfilesDir) 'precondition: repo dir should not exist'

    EnsureRepo

    Assert-Equals 1 $global:GitCalls.Count
    Assert-Equals 'clone' $global:GitCalls[0][0]
}

function test_ensurerepo_clones_into_empty_target {
    New-Item -ItemType Directory -Path $script:DotfilesDir | Out-Null

    EnsureRepo

    Assert-Equals 1 $global:GitCalls.Count
    Assert-Equals 'clone' $global:GitCalls[0][0]
}

function test_dotfiles_dir_override_does_not_need_to_exist {
    $missing = Join-Path $env:USERPROFILE 'missing-dotfiles'

    Assert-False (Test-Path $missing) 'precondition: override target should not exist'
    Assert-Equals $missing (Resolve-DotfilesDir $missing $script:DotfileScript)
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
