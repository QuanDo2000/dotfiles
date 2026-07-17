# SetupDotfiles and SetupSymlinks orchestration in dry mode.
# All external tools get mocked so the tests can't touch the real system.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    # Create the directory layout SetupSymlinks expects so path resolution works.
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows\Powershell') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows\Terminal') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared\.ssh') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\shared\config\nvim') -Force | Out-Null
    'starship' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\config\starship.toml')
    'profile' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\Powershell\Microsoft.PowerShell_profile.ps1')
    '{}' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\Terminal\settings.json')
    'gitconfig' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.gitconfig')
    'winconfig' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\.gitconfig')
    'ssh' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.ssh\config')
    'dotfile' | Set-Content (Join-Path $script:DotfilesDir 'dotfile.ps1')

    Set-CommandMock 'git' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'scoop' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'Invoke-WebRequest' { }
    Set-CommandMock 'Invoke-RestMethod' { }

    $script:Dry = $true
    $script:Quiet = $true
}

function TestTeardown {
    foreach ($c in 'git', 'winget', 'scoop', 'Invoke-WebRequest', 'Invoke-RestMethod') {
        Clear-CommandMock $c
    }
    Clear-TestEnv
}

function test_setupdotfiles_dry_run_completes_without_errors {
    # Should run through the full Windows setup chain without throwing.
    $err = $null
    try { SetupDotfiles } catch { $err = $_ }
    Assert-True ($null -eq $err) "SetupDotfiles should not throw in dry run, got: $err"
}

function test_installmanagedpackages_installs_all_managed_packages {
    $script:Calls = @()
    $originalInstallPackages = (Get-Command InstallPackages).ScriptBlock
    $originalInstallExtras = (Get-Command InstallExtras).ScriptBlock
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    Set-FunctionMock 'InstallPackages' { $script:Calls += 'winget' }
    Set-FunctionMock 'InstallExtras' { $script:Calls += 'extras' }
    Set-FunctionMock 'InstallAi' { $script:Calls += 'ai' }

    try {
        InstallManagedPackages
    } finally {
        Set-FunctionMock 'InstallPackages' $originalInstallPackages
        Set-FunctionMock 'InstallExtras' $originalInstallExtras
        Set-FunctionMock 'InstallAi' $originalInstallAi
    }

    Assert-Equals 'winget extras ai' ($script:Calls -join ' ')
}

function test_packages_dispatch_uses_managed_package_flow {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-True ($text -match '"packages"\s*\{\s*InstallManagedPackages\s*\}') 'packages should install every managed package group'
}

function test_setupdotfiles_updates_repo_before_installing_packages {
    $script:Dry = $false
    $script:Calls = @()
    $originalInstallManagedPackages = (Get-Command InstallManagedPackages).ScriptBlock
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $originalSetupSymlinks = (Get-Command SetupSymlinks).ScriptBlock
    $originalSyncLazyVim = (Get-Command Sync-LazyVim).ScriptBlock
    $originalAssertWindowsHealthy = if (Get-Command Assert-WindowsHealthy -ErrorAction SilentlyContinue) {
        (Get-Command Assert-WindowsHealthy).ScriptBlock
    } else { $null }
    Set-FunctionMock 'InstallManagedPackages' { $script:Calls += 'InstallManagedPackages' }
    Set-FunctionMock 'UpdateRepo' { $script:Calls += 'UpdateRepo' }
    Set-FunctionMock 'SetupSymlinks' { $script:Calls += 'SetupSymlinks' }
    Set-FunctionMock 'Sync-LazyVim' { $script:Calls += 'Sync-LazyVim' }
    Set-FunctionMock 'Assert-WindowsHealthy' { $script:Calls += 'Doctor' }

    try {
        SetupDotfiles
    } finally {
        Set-FunctionMock 'InstallManagedPackages' $originalInstallManagedPackages
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        Set-FunctionMock 'SetupSymlinks' $originalSetupSymlinks
        Set-FunctionMock 'Sync-LazyVim' $originalSyncLazyVim
        if ($originalAssertWindowsHealthy) {
            Set-FunctionMock 'Assert-WindowsHealthy' $originalAssertWindowsHealthy
        } else {
            Remove-Item function:\Assert-WindowsHealthy -ErrorAction SilentlyContinue
        }
    }

    Assert-Equals 'UpdateRepo' $script:Calls[0]
    Assert-Equals 'InstallManagedPackages' $script:Calls[1]
    Assert-Equals 'Sync-LazyVim' $script:Calls[3]
    Assert-Equals 'Doctor' $script:Calls[4]
}

function test_setupsymlinks_dry_run_creates_no_symlinks {
    # Dry mode: each LinkFile/LinkDir bails before creating anything.
    SetupSymlinks

    $psProfileDest = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    Assert-False (Test-Path $psProfileDest) 'no symlink should be created in dry run'
}

function test_setupsymlinks_links_starship_config {
    # The shared starship.toml should be wired to ~/.config/starship.toml, where
    # `starship init` reads it by default. Assert on the dry-run link intent so
    # the test needs no symlink privilege and mutates no real user state.
    $script:Quiet = $false
    $out = SetupSymlinks 6>&1 | Out-String

    $expectedSrc = Join-Path $script:DotfilesDir 'config\shared\config\starship.toml'
    $expectedDst = Join-Path $env:USERPROFILE '.config\starship.toml'
    Assert-Contains $out $expectedSrc
    Assert-Contains $out $expectedDst
}
