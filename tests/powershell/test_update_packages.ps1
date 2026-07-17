# Windows Winget package update tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

# ---------------------------------------------------------------------------
# Package list
# ---------------------------------------------------------------------------

function test_windows_packages_include_neovim {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text '"Neovim.Neovim"'
}

function test_windows_packages_use_exact_powershell_id {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text '"Microsoft.PowerShell"'
    Assert-False ($text -clike '*"Microsoft.Powershell"*') 'PowerShell package ID casing must match winget exactly'
}

function test_winget_commands_use_shared_helper {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'function Invoke-Winget'
    Assert-False ($text -match '\{ winget (install|upgrade)') 'raw winget install/upgrade calls should go through Invoke-Winget'
}

function test_update_packages_updates_repo_before_loading_updated_installer {
    $script:Dry = $false
    $script:Calls = @()
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $originalUpdatedInstall = (Get-Command Invoke-UpdatedPackageInstall).ScriptBlock
    Set-FunctionMock 'UpdateRepo' { $script:Calls += 'repo' }
    Set-FunctionMock 'Invoke-UpdatedPackageInstall' { $script:Calls += 'updated' }

    try {
        Update-Packages 6>&1 | Out-Null
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        Set-FunctionMock 'Invoke-UpdatedPackageInstall' $originalUpdatedInstall
    }

    Assert-Equals 'repo updated' ($script:Calls -join ' ')
}

function test_update_packages_reloads_packages_declared_by_repo_update {
    $script:Dry = $false
    $script:RepoUpdates = 0
    $script:WingetCalls = @()
    $originalDotfilesDir = $script:DotfilesDir
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $originalInstallExtras = (Get-Command InstallExtras).ScriptBlock
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalSyncLazyVimConfig = (Get-Command Sync-LazyVimConfig).ScriptBlock
    $originalSyncLazyVim = (Get-Command Sync-LazyVim).ScriptBlock
    $originalAssertWindowsHealthy = (Get-Command Assert-WindowsHealthy).ScriptBlock
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'pulled-dotfiles'
    New-Item -ItemType Directory -Force -Path $script:DotfilesDir | Out-Null
    Copy-Item -LiteralPath $script:DotfileScript -Destination (Join-Path $script:DotfilesDir 'dotfile.ps1')
    $script:PulledScript = (Get-Content -Raw $script:DotfileScript).Replace(
        '"Python.Python.3.14", "GitHub.cli"',
        '"Python.Python.3.14", "GitHub.cli", "Example.NewPackage"'
    ) + @'

function InstallExtras { param([switch]$Update) }
function InstallAi { param([switch]$Update) }
function Sync-LazyVimConfig { }
function Sync-LazyVim { }
function Assert-WindowsHealthy { }
'@
    Set-FunctionMock 'UpdateRepo' {
        $script:RepoUpdates++
        Set-Content -LiteralPath (Join-Path $script:DotfilesDir 'dotfile.ps1') -Value $script:PulledScript
    }
    Set-FunctionMock 'InstallExtras' { param([switch]$Update) }
    Set-FunctionMock 'InstallAi' { param([switch]$Update) }
    Set-FunctionMock 'Sync-LazyVimConfig' { }
    Set-FunctionMock 'Sync-LazyVim' { }
    Set-FunctionMock 'Assert-WindowsHealthy' { }
    Set-CommandMock 'winget' {
        $call = $args -join ' '
        $script:WingetCalls += ,$call
        if ($args[0] -eq 'list' -and $args[2] -eq 'Example.NewPackage') {
            $global:LASTEXITCODE = 1
        } else {
            $global:LASTEXITCODE = 0
        }
    }

    try {
        Update-Packages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        Set-FunctionMock 'InstallExtras' $originalInstallExtras
        Set-FunctionMock 'InstallAi' $originalInstallAi
        Set-FunctionMock 'Sync-LazyVimConfig' $originalSyncLazyVimConfig
        Set-FunctionMock 'Sync-LazyVim' $originalSyncLazyVim
        Set-FunctionMock 'Assert-WindowsHealthy' $originalAssertWindowsHealthy
        $script:DotfilesDir = $originalDotfilesDir
    }

    Assert-Equals 1 $script:RepoUpdates
    Assert-True ($script:WingetCalls -like 'install --id Example.NewPackage --exact*') 'update should install a package declared by the pull'
}

function test_update_packages_dry_run_does_not_call_winget {
    $script:Dry = $true
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }

    try {
        $output = Invoke-UpdatedPackageInstall $script:DotfileScript $true $false $false 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'winget'
    }

    Assert-Contains $output 'Installing packages'
    Assert-Contains $output 'Installing Scoop packages'
    Assert-Contains $output 'Installing Node.js LTS'
    Assert-Contains $output 'Installing or updating LazyVim'
    Assert-False $script:Called 'winget should not be invoked in dry run'
}

function test_installpackages_fails_when_winget_install_fails {
    $script:Dry = $false
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-FunctionMock 'WingetHas' { return $false }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallPackages 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'WingetHas' $originalWingetHas
    }

    Assert-True $failed 'InstallPackages should fail when winget install fails'
}

function test_installpackages_upgrades_all_winget_packages {
    $script:Dry = $false
    $script:WingetCalls = @()
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-FunctionMock 'WingetHas' { return $true }
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    try {
        InstallPackages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'WingetHas' $originalWingetHas
    }

    Assert-Equals 1 $script:WingetCalls.Count
    Assert-Contains $script:WingetCalls[0] 'upgrade --all'
    Assert-Contains $script:WingetCalls[0] '--accept-source-agreements'
}

function test_installpackages_fails_when_winget_upgrade_fails {
    $script:Dry = $false
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-FunctionMock 'WingetHas' { return $true }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallPackages 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'WingetHas' $originalWingetHas
    }

    Assert-True $failed 'InstallPackages should fail when winget upgrade fails'
}

function test_installpackages_installs_missing_winget_packages_individually {
    $script:Dry = $false
    $script:MissingWingetPackages = @('Git.Git', 'Neovim.Neovim')
    $script:InstallCalls = @()
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-FunctionMock 'WingetHas' { param($id) return ($script:MissingWingetPackages -notcontains $id) }
    Set-CommandMock 'winget' {
        if ($args[0] -eq 'install') { $script:InstallCalls += ,($args -join ' ') }
        $global:LASTEXITCODE = 0
    }

    try {
        InstallPackages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'WingetHas' $originalWingetHas
        Remove-Variable -Name MissingWingetPackages -Scope Script -ErrorAction SilentlyContinue
    }

    Assert-Equals 2 $script:InstallCalls.Count
    Assert-Contains $script:InstallCalls[0] 'install --id Git.Git --exact'
    Assert-Contains $script:InstallCalls[0] '--accept-source-agreements'
    Assert-Contains $script:InstallCalls[1] 'install --id Neovim.Neovim --exact'
    Assert-Contains $script:InstallCalls[1] '--accept-source-agreements'
}
