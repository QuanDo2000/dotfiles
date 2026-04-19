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
    'profile' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\Powershell\Microsoft.PowerShell_profile.ps1')
    '{}' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\Terminal\settings.json')
    'gvim' | Set-Content (Join-Path $script:DotfilesDir 'config\windows\_gvimrc')
    'vim' | Set-Content (Join-Path $script:DotfilesDir 'config\shared\.vimrc')
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
    # Should run through all four stages (packages/update/extras/symlinks) without throwing.
    $err = $null
    try { SetupDotfiles } catch { $err = $_ }
    Assert-True ($null -eq $err) "SetupDotfiles should not throw in dry run, got: $err"
}

function test_setupsymlinks_dry_run_creates_no_symlinks {
    # Dry mode: each LinkFile/LinkDir bails before creating anything.
    SetupSymlinks

    $psProfileDest = Join-Path $env:USERPROFILE 'documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    Assert-False (Test-Path $psProfileDest) 'no symlink should be created in dry run'
}
