# Windows Winget package update tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_update_packages_dry_run_does_not_call_winget {
    $script:Dry = $true
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }

    try {
        $output = Update-Packages 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'winget'
    }

    Assert-Contains $output 'Would run: winget upgrade --all'
    Assert-False $script:Called 'winget should not be invoked in dry run'
}

function test_update_packages_fails_when_winget_upgrade_fails {
    $script:Dry = $false
    $script:WingetCalls = @()
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 1
    }
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    Set-FunctionMock 'InstallAi' { }

    $failed = $false
    try {
        Update-Packages 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'InstallAi' $originalInstallAi
    }

    Assert-True $failed 'Update-Packages should fail when winget upgrade fails'
    Assert-Contains $script:WingetCalls[0] '--accept-source-agreements'
}

# ---------------------------------------------------------------------------
# Package list
# ---------------------------------------------------------------------------

function test_windows_packages_include_neovim {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text '"Neovim.Neovim"'
}

function test_winget_commands_use_shared_helper {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'function Invoke-Winget'
    Assert-False ($text -match '\{ winget (install|upgrade)') 'raw winget install/upgrade calls should go through Invoke-Winget'
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
