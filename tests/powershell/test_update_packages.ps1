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

function test_installpackages_upgrades_only_managed_winget_packages {
    $script:Dry = $false
    $script:WingetCalls = @()
    Set-FunctionMock 'WingetHas' { return $true }
    Set-CommandMock 'winget' {
        $script:WingetCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    InstallPackages 6>&1 | Out-Null

    $managed = @(Get-WingetPackages)
    Assert-Equals $managed.Count $script:WingetCalls.Count
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
