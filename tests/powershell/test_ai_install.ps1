# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    foreach ($command in 'npm', 'py', 'jq') {
        Clear-CommandMock $command
    }
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
    $seedDir = Join-Path $script:DotfilesDir 'config\windows\ai\codex'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    'model = "gpt-5.6-sol"' | Set-Content (Join-Path $seedDir 'config.toml')

    SyncCodexConfig

    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    Assert-FileExists $target
    Assert-False ([bool](Get-Item $target).LinkType) 'Codex config should stay writable'
}

function test_synccodexconfig_clears_readonly_attribute_from_seed_copy {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\windows\ai\codex'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    $source = Join-Path $seedDir 'config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    'model = "gpt-5.6-sol"' | Set-Content $source

    try {
        (Get-Item $source).IsReadOnly = $true
        SyncCodexConfig

        Assert-False (Get-Item $target).IsReadOnly 'Codex config should stay writable when the seed is read-only'
    } finally {
        if (Test-Path -LiteralPath $source) { (Get-Item $source).IsReadOnly = $false }
        if (Test-Path -LiteralPath $target) { (Get-Item $target).IsReadOnly = $false }
    }
}

function test_installai_fails_when_codebase_memory_update_fails {
    $script:Dry = $false
    $originalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'mock-codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallAi -Update 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'codebase-memory-mcp'
        Clear-CommandMock 'Get-Command'
        Set-Item -Path function:global:InstallCodex -Value $originalInstallCodex
    }

    Assert-True $failed 'InstallAi should fail when codebase-memory-mcp update fails'
}

function test_installai_fails_when_codebase_memory_install_fails {
    $script:Dry = $false
    $originalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'irm' { 'function global:codebase-memory-mcp { $global:LASTEXITCODE = 1 }; codebase-memory-mcp install' }

    $failed = $false
    try {
        InstallAi 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'irm'
        Clear-CommandMock 'Get-Command'
        Clear-CommandMock 'codebase-memory-mcp'
        Set-Item -Path function:global:InstallCodex -Value $originalInstallCodex
    }

    Assert-True $failed 'InstallAi should fail when codebase-memory-mcp install script fails'
}

function test_installcodex_fails_when_installer_exits_nonzero {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codex') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-RestMethod' { '$global:LASTEXITCODE = 1' }

    $failed = $false
    try {
        InstallCodex 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'Invoke-RestMethod'
        Clear-CommandMock 'Get-Command'
    }

    Assert-True $failed 'InstallCodex should fail when installer exits nonzero'
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
        return Microsoft.PowerShell.CoreGet-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' {
        $script:NpmCalls += ,($args -join ' ')
        $script:PiInstalled = $true
        $global:LASTEXITCODE = 0
    }

    try {
        InstallPi
    } finally {
        Clear-CommandMock 'Get-Command'
    }

    Assert-Contains $script:NpmCalls[0] 'install --global @earendil-works/pi-coding-agent'
}

function test_installpi_fails_when_command_is_missing_after_install {
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return $null }
        return Microsoft.PowerShell.CoreGet-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' { $global:LASTEXITCODE = 0 }

    $failed = $false
    $message = ''
    try {
        InstallPi
    } catch {
        $failed = $true
        $message = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Get-Command'
    }

    Assert-True $failed 'Pi installation should fail when pi is still unavailable'
    Assert-Contains $message 'pi command not found after installation'
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
