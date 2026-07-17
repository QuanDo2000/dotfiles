# Windows Winget package update tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:OriginalWingetHas = (Get-Command WingetHas).ScriptBlock
}

function TestTeardown {
    Clear-CommandMock 'winget'
    Set-FunctionMock 'WingetHas' $script:OriginalWingetHas
    Remove-Variable -Name MissingWingetPackages, AllInstalled -Scope Script -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function test_update_packages_reloads_installer_from_repo_update {
    $script:Dry = $true
    $global:UpdatedInstallerRan = $false
    $originalDotfilesDir = $script:DotfilesDir
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'pulled-dotfiles'
    New-Item -ItemType Directory -Force -Path $script:DotfilesDir | Out-Null
    Set-FunctionMock 'UpdateRepo' {
        @'
param([switch]$NoMain, [switch]$Dry, [switch]$Force, [switch]$Quiet)
function InstallPackages { $global:UpdatedInstallerRan = $true }
function InstallExtras { param([switch]$Update) }
function InstallAi { param([switch]$Update) }
function Sync-LazyVimConfig { }
function Sync-LazyVim { }
'@ | Set-Content -LiteralPath (Join-Path $script:DotfilesDir 'dotfile.ps1')
    }

    try {
        Update-Packages 6>&1 | Out-Null
        $updatedInstallerRan = $global:UpdatedInstallerRan
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        $script:DotfilesDir = $originalDotfilesDir
        Remove-Variable UpdatedInstallerRan -Scope Global
    }

    Assert-True $updatedInstallerRan 'update should run the installer loaded after the pull'
}

function test_update_packages_dry_run_does_not_call_winget {
    $script:Dry = $true
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }

    Invoke-UpdatedPackageInstall $script:DotfileScript $true $false $false 6>&1 | Out-Null

    Assert-False $script:Called 'winget should not be invoked in dry run'
}

function test_installpackages_upgrades_all_winget_packages {
    $script:Dry = $false
    $script:WingetCalls = @()
    Set-FunctionMock 'WingetHas' { return $true }
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    InstallPackages 6>&1 | Out-Null

    Assert-Equals 1 $script:WingetCalls.Count
    Assert-Contains $script:WingetCalls[0] 'upgrade --all'
    Assert-Contains $script:WingetCalls[0] '--accept-source-agreements'
}

function test_installpackages_propagates_winget_failures {
    $script:Dry = $false
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }

    foreach ($allInstalled in $false, $true) {
        $script:AllInstalled = $allInstalled
        Set-FunctionMock 'WingetHas' { return $script:AllInstalled }
        Assert-Throws { InstallPackages 6>&1 | Out-Null } 'InstallPackages should propagate Winget failures'
    }
}

function test_installpackages_installs_missing_winget_packages_individually {
    $script:Dry = $false
    $script:MissingWingetPackages = @('Git.Git', 'Neovim.Neovim')
    $script:InstallCalls = @()
    Set-FunctionMock 'WingetHas' { param($id) return ($script:MissingWingetPackages -notcontains $id) }
    Set-CommandMock 'winget' {
        if ($args[0] -eq 'install') { $script:InstallCalls += ,($args -join ' ') }
        $global:LASTEXITCODE = 0
    }

    InstallPackages 6>&1 | Out-Null

    Assert-Equals 2 $script:InstallCalls.Count
    Assert-Contains $script:InstallCalls[0] 'install --id Git.Git --exact'
    Assert-Contains $script:InstallCalls[0] '--accept-source-agreements'
    Assert-Contains $script:InstallCalls[1] 'install --id Neovim.Neovim --exact'
    Assert-Contains $script:InstallCalls[1] '--accept-source-agreements'
}
