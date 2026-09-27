# Windows Winget package update tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    Set-CommandMock 'Get-Process' {
        param($Name, $Id)
        if ($Id) { Microsoft.PowerShell.Management\Get-Process -Id $Id }
    }
    $script:OriginalProgramFiles = $env:ProgramFiles
    $env:ProgramFiles = Join-Path $env:USERPROFILE 'Program Files'
    $script:OriginalGetInstalledWingetPackages = (Get-Command Get-InstalledWingetPackages).ScriptBlock
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
    Set-FunctionMock 'AddToUserPath' { }
}

function TestTeardown {
    Clear-CommandMock 'winget'
    Clear-CommandMock 'rustup'
    Clear-CommandMock 'Get-Process'
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

function test_ai_only_update_does_not_require_unrelated_packages {
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalHealth = (Get-Command Assert-WindowsHealthy).ScriptBlock
    $script:Dry = $false
    $script:AiInstalled = $false
    Set-FunctionMock 'InstallAi' { param([switch]$Update) $script:AiInstalled = [bool]$Update }
    Set-FunctionMock 'Assert-WindowsHealthy' { throw 'Unrelated Windows package missing' }
    try {
        Update-Packages ai -AfterRepoUpdate 6>&1 | Out-Null
    } finally {
        Set-FunctionMock 'InstallAi' $originalInstallAi
        Set-FunctionMock 'Assert-WindowsHealthy' $originalHealth
    }
    Assert-True $script:AiInstalled 'AI-only update must run the AI installer in update mode'
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

function test_installpackages_skips_upgrades_outside_update {
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

    Assert-Equals 1 $script:WingetCalls.Count
    Assert-True ($script:WingetCalls[0] -like 'export *') 'package install should inventory managed packages'
    Assert-False ($script:WingetCalls[0] -like '*--ignore-unavailable*') 'winget export must use supported options'
}

function test_installpackages_update_upgrades_only_managed_packages {
    $script:Dry = $false
    $script:WingetCalls = @()
    $script:RustupCalls = @()
    Set-CommandMock 'rustup' { $script:RustupCalls += ,($args -join ' '); $global:LASTEXITCODE = 0 }
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        if ($args[0] -eq 'export') {
            $outputIndex = [Array]::IndexOf($args, '--output')
            '{"Sources":[{"Packages":[' + ((Get-WingetPackages | ForEach-Object { '{"PackageIdentifier":"' + $_ + '"}' }) -join ',') + ']}]}' |
                Set-Content -LiteralPath $args[$outputIndex + 1]
        }
        $global:LASTEXITCODE = 0
    }

    InstallPackages -Update 6>&1 | Out-Null

    $managed = @(Get-WingetPackages)
    Assert-Equals ($managed.Count + 1) $script:WingetCalls.Count
    Assert-False (($script:WingetCalls -join "`n") -like '*upgrade --all*') 'unmanaged packages should not be upgraded'
    foreach ($package in $managed) {
        Assert-True ($script:WingetCalls -contains "upgrade --id $package --exact --disable-interactivity --accept-package-agreements --accept-source-agreements") "missing managed upgrade for $package"
    }
    Assert-Equals 1 $script:RustupCalls.Count
    Assert-Equals 'update stable' $script:RustupCalls[0]
}

function test_installpackages_update_reports_rust_toolchain_failure {
    $script:Dry = $false
    Set-FunctionMock 'Get-InstalledWingetPackages' { return @(Get-WingetPackages) }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'rustup' { $global:LASTEXITCODE = 1 }

    $message = ''
    try { InstallPackages -Update 6>&1 | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Contains $message 'rustup update stable failed'
}

function test_native_upgrade_dry_run_never_calls_winget {
    $script:Dry = $true
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }

    UpgradeNativePackages 6>&1 | Out-Null

    Assert-False $script:Called 'dry run must not call winget'
}

function test_native_upgrade_runs_all_winget_packages_without_setup {
    $script:WingetCalls = @()
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    UpgradeNativePackages 6>&1 | Out-Null

    Assert-Equals 1 $script:WingetCalls.Count
    Assert-Equals 'upgrade --all --disable-interactivity --accept-package-agreements --accept-source-agreements' $script:WingetCalls[0]
}

function test_native_upgrade_fails_before_winget_when_anki_is_running {
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }
    Set-CommandMock 'Get-Process' { param($Name) if ($Name -eq 'anki') { [pscustomobject]@{ Name = 'anki' } } }

    $message = ''
    try { UpgradeNativePackages 6>&1 | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Contains $message 'Close Anki before installing or updating Anki'
    Assert-False $script:Called 'upgrade must stop before invoking winget'
}

function test_native_upgrade_fails_before_winget_when_obsidian_is_running {
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }
    Set-CommandMock 'Get-Process' { param($Name) if ($Name -eq 'Obsidian') { [pscustomobject]@{ Name = 'Obsidian' } } }

    $message = ''
    try { UpgradeNativePackages 6>&1 | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Contains $message 'Close Obsidian before updating its application'
    Assert-False $script:Called 'upgrade must stop before invoking winget'
}

function test_native_upgrade_propagates_winget_failure {
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }
    $message = ''
    try { UpgradeNativePackages 6>&1 | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Contains $message 'winget upgrade failed'
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

function test_installpackages_adds_compiler_tools_to_user_path {
    $script:Dry = $false
    $script:AddedUserPaths = @()
    Set-FunctionMock 'Get-InstalledWingetPackages' { return @(Get-WingetPackages) }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    Set-FunctionMock 'AddToUserPath' { param($dir) $script:AddedUserPaths += $dir }

    InstallPackages 6>&1 | Out-Null

    Assert-Equals 2 $script:AddedUserPaths.Count
    Assert-True ($script:AddedUserPaths -contains (Join-Path $env:ProgramFiles 'LLVM\bin')) 'LLVM should be on user PATH'
    Assert-True ($script:AddedUserPaths -contains (Join-Path $env:USERPROFILE '.cargo\bin')) 'Rust tools should be on user PATH'
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

    Assert-Throws { InstallPackages -Update 6>&1 | Out-Null } 'InstallPackages should propagate Winget upgrade failures'
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
