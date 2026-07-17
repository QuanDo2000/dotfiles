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

function test_update_packages_installs_declared_packages_before_updates {
    $script:Dry = $false
    $script:Calls = @()
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $originalInstallPackages = (Get-Command InstallPackages).ScriptBlock
    $originalInstallExtras = (Get-Command InstallExtras).ScriptBlock
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalSyncLazyVimConfig = (Get-Command Sync-LazyVimConfig).ScriptBlock
    $originalSyncLazyVim = (Get-Command Sync-LazyVim).ScriptBlock
    $originalAssertWindowsHealthy = if (Get-Command Assert-WindowsHealthy -ErrorAction SilentlyContinue) {
        (Get-Command Assert-WindowsHealthy).ScriptBlock
    } else { $null }
    Set-FunctionMock 'UpdateRepo' { $script:Calls += 'repo' }
    Set-FunctionMock 'InstallPackages' { $script:Calls += 'winget' }
    Set-FunctionMock 'InstallExtras' { param([switch]$Update) if ($Update) { $script:Calls += 'extras' } }
    Set-FunctionMock 'InstallAi' { param([switch]$Update) if ($Update) { $script:Calls += 'ai' } }
    Set-FunctionMock 'Sync-LazyVimConfig' { $script:Calls += 'config' }
    Set-FunctionMock 'Sync-LazyVim' { $script:Calls += 'lazy' }
    Set-FunctionMock 'Assert-WindowsHealthy' { $script:Calls += 'doctor' }

    try {
        Update-Packages 6>&1 | Out-Null
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        Set-FunctionMock 'InstallPackages' $originalInstallPackages
        Set-FunctionMock 'InstallExtras' $originalInstallExtras
        Set-FunctionMock 'InstallAi' $originalInstallAi
        Set-FunctionMock 'Sync-LazyVimConfig' $originalSyncLazyVimConfig
        Set-FunctionMock 'Sync-LazyVim' $originalSyncLazyVim
        if ($originalAssertWindowsHealthy) {
            Set-FunctionMock 'Assert-WindowsHealthy' $originalAssertWindowsHealthy
        } else {
            Remove-Item function:\Assert-WindowsHealthy -ErrorAction SilentlyContinue
        }
    }

    Assert-Equals 'repo winget extras ai config lazy doctor' ($script:Calls -join ' ')
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
