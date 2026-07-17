# Verify — drives the function end-to-end with mocked lookups. Verify uses
# $env:USERPROFILE (overridden by Initialize-TestEnv) so it operates on the
# temp home; tests still focus on control-flow coverage rather than asserting
# specific file-existence outcomes.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    New-Item -ItemType Directory -Path (Join-Path $script:DotfilesDir 'config\windows\Powershell') -Force | Out-Null
    # Verify's informational output flows through Info/Success, which are
    # gated by $script:Quiet. Keep Quiet off so 6>&1 captures the banners the
    # assertions look for.
    $script:Quiet = $false
    Set-CommandMock 'scoop' {
        $global:LASTEXITCODE = 0
        Get-ScoopPackages | ForEach-Object { [pscustomobject]@{ Name = $_ } }
    }
    $script:OriginalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-FunctionMock 'WingetHas' { return $true }
    Set-HealthyToolMocks
}

function Set-HealthyToolMocks {
    Set-CommandMock 'Get-Command' { param($Name) [pscustomobject]@{ Source = "C:\fake\$Name.exe" } }
    Set-CommandMock 'Get-Module' { [pscustomobject]@{ Name = 'FakeModule' } }
}

function TestTeardown {
    Clear-CommandMock 'Get-Command'
    Clear-CommandMock 'Get-Module'
    Clear-CommandMock 'scoop'
    Set-FunctionMock 'WingetHas' $script:OriginalWingetHas
    Clear-TestEnv
}

function test_verify_reports_missing_installation {
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Get-Module' { return $null }

    $output = Verify 6>&1 | Out-String

    foreach ($text in 'Verifying installed tools', 'Verifying scoop packages', 'Verifying PowerShell modules', 'Verifying managed links', 'starship.toml', 'not found', 'issue') {
        Assert-Contains $output $text
    }
    Assert-True $script:VerifyFailed 'missing installation should fail verification'
}

function test_verify_checks_every_managed_link_spec {
    $script:ManagedLinkSource = Join-Path $env:USERPROFILE 'source.txt'
    $script:ManagedLinkDestination = Join-Path $env:USERPROFILE 'destination.txt'
    'same' | Set-Content $script:ManagedLinkSource
    'same' | Set-Content $script:ManagedLinkDestination
    $originalGetWindowsLinkSpecs = (Microsoft.PowerShell.Core\Get-Command Get-WindowsLinkSpecs).ScriptBlock
    Set-FunctionMock 'Get-WindowsLinkSpecs' {
        @(New-LinkSpec 'File' $script:ManagedLinkSource $script:ManagedLinkDestination)
    }

    try {
        $output = Verify 6>&1 | Out-String
    } finally {
        Set-FunctionMock 'Get-WindowsLinkSpecs' $originalGetWindowsLinkSpecs
    }

    Assert-Contains $output 'is not linked to'
    Assert-True $script:VerifyFailed 'matching file contents must not substitute for a managed link'
}

function test_verify_reports_missing_managed_ai_command {
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return $null }
        [pscustomobject]@{ Source = "C:\fake\$Name.exe" }
    }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'codebase-memory-mcp not found'
    Assert-True $script:VerifyFailed 'missing managed AI command should fail verification'
}

function test_verify_reports_missing_codex_config {
    $output = Verify 6>&1 | Out-String

    Assert-Contains $output '.codex\config.toml'
    Assert-True $script:VerifyFailed 'missing Codex config should fail verification'
}

function test_verify_rejects_codex_config_directory {
    New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE '.codex\config.toml') | Out-Null

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'config.toml must be a regular writable file'
    Assert-True $script:VerifyFailed 'a Codex config directory should fail verification'
}

function test_verify_rejects_readonly_codex_config {
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    'model = "test"' | Set-Content $target
    (Get-Item -LiteralPath $target).IsReadOnly = $true

    try {
        $output = Verify 6>&1 | Out-String
    } finally {
        (Get-Item -LiteralPath $target).IsReadOnly = $false
    }

    Assert-Contains $output 'config.toml must be a regular writable file'
    Assert-True $script:VerifyFailed 'a read-only Codex config should fail verification'
}

function test_verify_rejects_codex_config_symlink {
    $source = Join-Path $env:USERPROFILE 'codex-source.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    'model = "test"' | Set-Content $source
    try {
        New-Item -ItemType SymbolicLink -Path $target -Target $source -ErrorAction Stop | Out-Null
    } catch {
        if ($_.Exception.Message -match 'privilege|Administrator') { return }
        throw
    }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'config.toml must be a regular writable file'
    Assert-True $script:VerifyFailed 'a symlinked Codex config should fail verification'
}

function test_verify_checks_exact_winget_packages {
    Set-FunctionMock 'WingetHas' { param($id) return ($id -ne 'Microsoft.PowerShell') }

    $output = Verify 6>&1 | Out-String

    Assert-Contains $output 'Winget package missing: Microsoft.PowerShell'
    Assert-True $script:VerifyFailed 'missing exact Winget package should fail verification'
}
