# SetupDotfiles and managed-link smoke tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    foreach ($path in 'config\windows\Powershell', 'config\windows\Notepad++\themes') {
        New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir $path) -Force | Out-Null
    }
    $script:Dry = $true
    $script:Quiet = $true
}

function TestTeardown {
    Clear-TestEnv
}

function test_setupdotfiles_dry_run_completes_without_errors {
    SetupDotfiles -AfterRepoUpdate
}

function test_setupdotfiles_starts_pulled_script_in_fresh_process {
    $originalUpdateRepo = (Get-Command UpdateRepo).ScriptBlock
    $env:UPDATED_DOTFILE_MARKER = Join-Path $env:USERPROFILE 'updated-all-entrypoint.log'
    Set-FunctionMock 'UpdateRepo' {
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
[IO.File]::WriteAllText($env:UPDATED_DOTFILE_MARKER, "$Command|$UpdateTarget|$Dry")
'@ | Set-Content -LiteralPath (Join-Path $script:DotfilesDir 'dotfile.ps1')
    }

    try {
        SetupDotfiles 6>&1 | Out-Null
        $actual = Get-Content -Raw -LiteralPath $env:UPDATED_DOTFILE_MARKER
    } finally {
        Set-FunctionMock 'UpdateRepo' $originalUpdateRepo
        Remove-Item Env:UPDATED_DOTFILE_MARKER -ErrorAction SilentlyContinue
    }

    Assert-Equals 'all||True' $actual
}

function test_setupsymlinks_links_starship_config {
    $destination = Join-Path $env:USERPROFILE '.config\starship.toml'
    $spec = Get-WindowsLinkSpecs | Where-Object Destination -eq $destination

    Assert-Equals (Join-Path $script:DotfilesDir 'config\shared\config\starship.toml') $spec.Source
}
