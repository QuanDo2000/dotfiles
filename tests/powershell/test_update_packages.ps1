# Windows Winget package update tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:OriginalProgramFiles = $env:ProgramFiles
    $env:ProgramFiles = Join-Path $env:USERPROFILE 'Program Files'
    $script:OriginalGetInstalledWingetPackages = (Get-Command Get-InstalledWingetPackages).ScriptBlock
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
    Set-FunctionMock 'AddToUserPath' { }
}

function TestTeardown {
    Clear-CommandMock 'winget'
    Set-FunctionMock 'Get-InstalledWingetPackages' $script:OriginalGetInstalledWingetPackages
    Set-FunctionMock 'AddToUserPath' $script:OriginalAddToUserPath
    if ($null -eq $script:OriginalProgramFiles) { Remove-Item Env:ProgramFiles -ErrorAction SilentlyContinue }
    else { $env:ProgramFiles = $script:OriginalProgramFiles }
    Remove-Variable -Name MissingWingetPackages, AllInstalled, AddedUserPath, OriginalProgramFiles -Scope Script -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function test_refreshprocesspath_preserves_current_process_entries {
    $originalPath = $env:Path
    try {
        $env:Path = 'fnm-active;session-only'

        Refresh-ProcessPath

        Assert-Contains $env:Path 'fnm-active'
    } finally {
        $env:Path = $originalPath
    }
}

function test_assertwindowshealthy_preserves_caller_process_path {
    $originalDoctor = (Get-Command Doctor).ScriptBlock
    $originalPath = $env:Path
    Set-FunctionMock 'Doctor' {
        $env:Path = 'refreshed-for-verification'
        $script:VerifyFailed = $false
    }

    try {
        Assert-WindowsHealthy
        $actualPath = $env:Path
    } finally {
        Set-FunctionMock 'Doctor' $originalDoctor
        $env:Path = $originalPath
    }

    Assert-Equals $originalPath $actualPath
}

function Write-TestUpdatedEntrypoint($Path) {
    @'
param(
    [switch]$AfterUpdate,
    [switch]$NoMain,
    [switch]$Dry,
    [switch]$Force,
    [switch]$Quiet,
    [Parameter(Position = 0)][string]$Command = 'all',
    [Parameter(Position = 1)][string]$UpdateTarget = ''
)
if ($NoMain) { throw 'updated script must start in a fresh process' }
if (-not $AfterUpdate) { throw 'updated process missing recursion guard' }
if ($env:DOTFILE_AFTER_UPDATE -ne '1') { throw 'updated process missing parent sentinel' }
[IO.File]::WriteAllText($env:UPDATED_DOTFILE_MARKER, "$Command|$UpdateTarget|$Dry|$Force|$Quiet")
'@ | Set-Content -LiteralPath $Path
}

function test_update_packages_starts_pulled_script_in_fresh_process {
    $script:Dry = $true
    $script:Force = $true
    $script:Quiet = $true
    $originalDotfilesDir = $script:DotfilesDir
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'pulled-dotfiles'
    $env:UPDATED_DOTFILE_MARKER = Join-Path $env:USERPROFILE 'updated-entrypoint.log'
    New-Item -ItemType Directory -Force -Path $script:DotfilesDir | Out-Null
    Set-FunctionMock 'UpdateRepo' {
        Write-TestUpdatedEntrypoint (Join-Path $script:DotfilesDir 'dotfile.ps1')
    }

    try {
        Update-Packages 6>&1 | Out-Null
        $actual = Get-Content -Raw -LiteralPath $env:UPDATED_DOTFILE_MARKER
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        $script:DotfilesDir = $originalDotfilesDir
        Remove-Item Env:UPDATED_DOTFILE_MARKER -ErrorAction SilentlyContinue
    }

    Assert-Equals 'update||True|True|True' $actual
}

function test_update_ai_preserves_target_in_fresh_process {
    $script:Dry = $true
    $originalDotfilesDir = $script:DotfilesDir
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'pulled-dotfiles'
    $env:UPDATED_DOTFILE_MARKER = Join-Path $env:USERPROFILE 'updated-ai-entrypoint.log'
    New-Item -ItemType Directory -Force -Path $script:DotfilesDir | Out-Null
    Set-FunctionMock 'UpdateRepo' {
        Write-TestUpdatedEntrypoint (Join-Path $script:DotfilesDir 'dotfile.ps1')
    }

    try {
        Update-Packages ai 6>&1 | Out-Null
        $actual = Get-Content -Raw -LiteralPath $env:UPDATED_DOTFILE_MARKER
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        $script:DotfilesDir = $originalDotfilesDir
        Remove-Item Env:UPDATED_DOTFILE_MARKER -ErrorAction SilentlyContinue
    }

    Assert-Equals 'update|ai|True|False|False' $actual
}

function test_update_packages_propagates_updated_process_failure {
    $script:Dry = $true
    $originalDotfilesDir = $script:DotfilesDir
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'failed-pulled-dotfiles'
    New-Item -ItemType Directory -Force -Path $script:DotfilesDir | Out-Null
    Set-FunctionMock 'UpdateRepo' {
        'param([switch]$AfterUpdate); exit 23' | Set-Content -LiteralPath (Join-Path $script:DotfilesDir 'dotfile.ps1')
    }

    $message = ''
    try {
        Update-Packages 6>&1 | Out-Null
    } catch {
        $message = $_.Exception.Message
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        $script:DotfilesDir = $originalDotfilesDir
    }

    Assert-Contains $message 'exit code 23'
}

function test_update_packages_dry_run_does_not_call_winget {
    $script:Dry = $true
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }
    New-Item -ItemType Directory -Force -Path @(
        (Join-Path $env:DOTFILES_DIR 'config\windows\Powershell'),
        (Join-Path $env:DOTFILES_DIR 'config\windows\Notepad++\themes')
    ) | Out-Null

    Update-Packages '' -AfterRepoUpdate 6>&1 | Out-Null

    Assert-False $script:Called 'winget should not be invoked in dry run'
}

function test_installpackages_inventories_winget_once_and_upgrades_only_managed_packages {
    $script:Dry = $false
    $script:WingetCalls = @()
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        if ($args[0] -eq 'export') {
            $outputIndex = [Array]::IndexOf($args, '--output')
            '{"Sources":[{"Packages":[' + ((Get-WingetPackages | ForEach-Object { '{"PackageIdentifier":"' + $_ + '"}' }) -join ',') + ']}]}' |
                Set-Content -LiteralPath $args[$outputIndex + 1]
        }
        $global:LASTEXITCODE = 0
    }

    InstallPackages 6>&1 | Out-Null

    $managed = @(Get-WingetPackages)
    Assert-Equals ($managed.Count + 1) $script:WingetCalls.Count
    Assert-Equals 1 @($script:WingetCalls | Where-Object { $_ -like 'export *' }).Count
    Assert-Contains $script:WingetCalls[0] '--ignore-unavailable'
    Assert-False (($script:WingetCalls -join "`n") -like '*upgrade --all*') 'unmanaged packages should not be upgraded'
    foreach ($package in $managed) {
        Assert-True ($script:WingetCalls -contains "upgrade --id $package --exact --disable-interactivity --accept-package-agreements --accept-source-agreements") "missing managed upgrade for $package"
    }
}

function test_invokewinget_accepts_no_applicable_upgrade {
    Set-CommandMock 'winget' { $global:LASTEXITCODE = -1978335189 }
    $threw = $false

    try {
        Invoke-Winget 'current package should not fail' @('upgrade', '--id', 'Microsoft.PowerShell', '--exact')
    } catch {
        $threw = $true
    }

    Assert-False $threw 'Winget no-applicable-update exit should be accepted for upgrades'
}

function test_installpackages_adds_llvm_to_user_path {
    $script:Dry = $false
    $script:AddedUserPath = $null
    Set-FunctionMock 'Get-InstalledWingetPackages' { return @(Get-WingetPackages) }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    Set-FunctionMock 'AddToUserPath' { param($dir) $script:AddedUserPath = $dir }

    InstallPackages 6>&1 | Out-Null

    Assert-Equals (Join-Path $env:ProgramFiles 'LLVM\bin') $script:AddedUserPath
}

function test_installpackages_propagates_winget_install_failure {
    $script:Dry = $false
    Set-FunctionMock 'Get-InstalledWingetPackages' { return @() }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = if ($args[0] -eq 'install') { 1 } else { 0 } }

    Assert-Throws { InstallPackages 6>&1 | Out-Null } 'InstallPackages should propagate Winget install failures'
}

function test_installpackages_propagates_winget_upgrade_failure {
    $script:Dry = $false
    Set-FunctionMock 'Get-InstalledWingetPackages' { return @(Get-WingetPackages) }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = if ($args[0] -eq 'upgrade') { 1 } else { 0 } }

    Assert-Throws { InstallPackages 6>&1 | Out-Null } 'InstallPackages should propagate Winget upgrade failures'
}

function test_installpackages_installs_missing_winget_packages_individually {
    $script:Dry = $false
    $script:MissingWingetPackages = @('Git.Git', 'Neovim.Neovim')
    $script:InstallCalls = @()
    Set-FunctionMock 'Get-InstalledWingetPackages' {
        $installed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($package in Get-WingetPackages) {
            if ($script:MissingWingetPackages -notcontains $package) { $null = $installed.Add($package) }
        }
        return $installed
    }
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
