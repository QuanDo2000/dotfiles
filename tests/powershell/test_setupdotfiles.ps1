# SetupDotfiles and managed-link smoke tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows\Powershell') -Force | Out-Null
    $script:Dry = $true
    $script:Quiet = $true
}

function TestTeardown {
    Clear-TestEnv
}

function test_setupdotfiles_dry_run_completes_without_errors {
    SetupDotfiles
}

function test_setupsymlinks_links_starship_config {
    $destination = Join-Path $env:USERPROFILE '.config\starship.toml'
    $spec = Get-WindowsLinkSpecs | Where-Object Destination -eq $destination

    Assert-Equals (Join-Path $script:DotfilesDir 'config\shared\config\starship.toml') $spec.Source
}
