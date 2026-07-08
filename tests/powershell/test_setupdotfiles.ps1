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

function test_setupdotfiles_updates_repo_before_installing_packages {
    $script:Calls = @()
    $originalInstallPackages = (Get-Command InstallPackages).ScriptBlock
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $originalInstallExtras = (Get-Command InstallExtras).ScriptBlock
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalSetupSymlinks = (Get-Command SetupSymlinks).ScriptBlock
    Set-Item -Path function:global:InstallPackages -Value { $script:Calls += 'InstallPackages' }
    Set-Item -Path function:global:UpdateRepo -Value { $script:Calls += 'UpdateRepo' }
    Set-Item -Path function:global:InstallExtras -Value { $script:Calls += 'InstallExtras' }
    Set-Item -Path function:global:InstallAi -Value { $script:Calls += 'InstallAi' }
    Set-Item -Path function:global:SetupSymlinks -Value { $script:Calls += 'SetupSymlinks' }

    try {
        SetupDotfiles
    } finally {
        Set-Item -Path function:global:InstallPackages -Value $originalInstallPackages
        Set-Item -Path function:global:UpdateRepo -Value $originalUpdateRepo
        Set-Item -Path function:global:InstallExtras -Value $originalInstallExtras
        Set-Item -Path function:global:InstallAi -Value $originalInstallAi
        Set-Item -Path function:global:SetupSymlinks -Value $originalSetupSymlinks
    }

    Assert-Equals 'UpdateRepo' $script:Calls[0]
    Assert-Equals 'InstallPackages' $script:Calls[1]
}

function test_setupsymlinks_dry_run_creates_no_symlinks {
    # Dry mode: each LinkFile/LinkDir bails before creating anything.
    SetupSymlinks

    $psProfileDest = Join-Path $env:USERPROFILE 'documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
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
