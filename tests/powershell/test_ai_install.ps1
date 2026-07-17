# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:OriginalInstallCodex = (Get-Command InstallCodex).ScriptBlock
}

function TestTeardown {
    foreach ($command in 'npm', 'py', 'jq', 'Get-Command', 'codebase-memory-mcp', 'irm', 'Invoke-RestMethod') {
        Clear-CommandMock $command
    }
    Set-Item -Path function:global:InstallCodex -Value $script:OriginalInstallCodex
    Remove-Variable -Name PiInstalled -Scope Script -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function test_windows_installs_codex_cli_with_official_installer {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'https://chatgpt.com/codex/install.ps1'
    Assert-Contains $text 'CODEX_NON_INTERACTIVE'
}

function test_synccodexconfig_creates_writable_seed_file {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent) | Out-Null
    'model = "gpt-5.6-sol"' | Set-Content $source

    try {
        (Get-Item $source).IsReadOnly = $true
        SyncCodexConfig

        Assert-FileExists $target
        Assert-False ([bool](Get-Item $target).LinkType) 'Codex config should be a regular file'
        Assert-False (Get-Item $target).IsReadOnly 'Codex config should be writable'
    } finally {
        foreach ($path in $source, $target) {
            if (Test-Path -LiteralPath $path) { (Get-Item $path).IsReadOnly = $false }
        }
    }
}

function test_installai_fails_when_codebase_memory_update_fails {
    $script:Dry = $false
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'mock-codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' { $global:LASTEXITCODE = 1 }

    Assert-Throws { InstallAi -Update 6>&1 | Out-Null } 'InstallAi should fail when codebase-memory-mcp update fails'
}

function test_installai_fails_when_codebase_memory_install_fails {
    $script:Dry = $false
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'irm' { 'function global:codebase-memory-mcp { $global:LASTEXITCODE = 1 }; codebase-memory-mcp install' }

    Assert-Throws { InstallAi 6>&1 | Out-Null } 'InstallAi should fail when codebase-memory-mcp install script fails'
}

function test_installcodex_fails_when_installer_exits_nonzero {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codex') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-RestMethod' { '$global:LASTEXITCODE = 1' }

    Assert-Throws { InstallCodex 6>&1 | Out-Null } 'InstallCodex should fail when installer exits nonzero'
}

function test_installpi_installs_official_package_and_checks_command {
    $script:PiInstalled = $false
    $script:NpmCalls = @()
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') {
            if ($script:PiInstalled) { return [pscustomobject]@{ Source = 'mock-pi' } }
            return $null
        }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' {
        $script:NpmCalls += ,($args -join ' ')
        $script:PiInstalled = $true
        $global:LASTEXITCODE = 0
    }

    InstallPi

    Assert-Contains $script:NpmCalls[0] 'install --global @earendil-works/pi-coding-agent'
}

function test_installpi_fails_when_command_is_missing_after_install {
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' { $global:LASTEXITCODE = 0 }

    Assert-Throws { InstallPi } 'Pi installation should fail when pi is still unavailable'
}

function test_syncpiconfigs_creates_writable_seed_files {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    '{"theme":"dark"}' | Set-Content (Join-Path $seedDir 'settings.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    'extension' | Set-Content (Join-Path $seedDir 'windows-exit.js')

    SyncPiConfigs

    $settings = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $mcp = Join-Path $env:USERPROFILE '.pi\agent\mcp.json'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    Assert-FileExists $settings
    Assert-FileExists $mcp
    Assert-FileExists (Join-Path $extensionDir 'codex-status.js')
    Assert-FileExists (Join-Path $extensionDir 'windows-exit.js')
    Assert-False ([bool](Get-Item $settings).LinkType) 'Pi settings should stay writable'
}
