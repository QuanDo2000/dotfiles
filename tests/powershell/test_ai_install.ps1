# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:OriginalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
}

function TestTeardown {
    foreach ($command in 'npm', 'npx', 'pi', 'py', 'jq', 'Get-Command', 'Get-FileHash', 'codebase-memory-mcp', 'irm', 'Invoke-RestMethod', 'Invoke-WebRequest') {
        Clear-CommandMock $command
    }
    Set-FunctionMock 'InstallCodex' $script:OriginalInstallCodex
    Set-FunctionMock 'AddToUserPath' $script:OriginalAddToUserPath
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

function test_installfffmcp_installs_verified_windows_binary_for_codex {
    $script:FffUrl = ''
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:FffUrl = $Uri
        'fff' | Set-Content -NoNewline $OutFile
    }
    Set-CommandMock 'Get-FileHash' {
        [pscustomobject]@{ Hash = '7ff688d034aa42ff779a61ad12689794bdc253c895152796046f374390fb9cad' }
    }
    Set-FunctionMock 'AddToUserPath' { }

    InstallFffMcp

    Assert-FileExists (Join-Path $env:USERPROFILE '.local\bin\fff-mcp.exe')
    Assert-Contains $script:FffUrl 'fff-mcp-x86_64-pc-windows-msvc.exe'
    Assert-Contains (Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\ai\codex\config.toml')) '[mcp_servers.fff]'
}

function test_syncaiinstructions_copies_shared_file_for_codex_and_pi {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $source = Join-Path $script:DotfilesDir 'config\shared\ai\AGENTS.md'
    New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent) | Out-Null
    'shared instructions' | Set-Content $source

    SyncAiInstructions

    foreach ($target in '.codex\AGENTS.md', '.pi\agent\AGENTS.md') {
        $path = Join-Path $env:USERPROFILE $target
        Assert-FileExists $path
        Assert-Contains (Get-Content -Raw $path) 'shared instructions'
    }
}

function test_installai_skills_installs_same_shared_skill_set {
    $script:NpxCalls = @()
    foreach ($skill in 'caveman', 'systematic-debugging', 'test-driven-development', 'verification-before-completion') {
        New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill") | Out-Null
    }
    Set-CommandMock 'npx' {
        $script:NpxCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    InstallAiSkills

    $calls = $script:NpxCalls -join "`n"
    foreach ($skill in 'caveman', 'systematic-debugging', 'test-driven-development', 'verification-before-completion') {
        Assert-Contains $calls "--skill $skill"
        Assert-False (Test-Path (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill")) "Stale Pi copy remains for $skill"
    }
    Assert-Contains $calls '--agent codex'
    Assert-False ($calls -like '*--agent pi*') 'Pi discovers shared ~/.agents/skills; a Pi-specific copy causes collisions'
}

function test_installai_fails_when_codebase_memory_update_fails {
    $script:Dry = $false
    $script:CodebaseMemoryCalls = @()
    $script:CodebaseMemoryInput = @()
    Set-FunctionMock 'InstallCodex' { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'mock-codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' {
        $script:CodebaseMemoryCalls += ,($args -join ' ')
        $script:CodebaseMemoryInput = @($input)
        $global:LASTEXITCODE = 1
    }

    Assert-Throws { InstallAi -Update 6>&1 | Out-Null } 'InstallAi should fail when codebase-memory-mcp update fails'
    Assert-True ($script:CodebaseMemoryCalls -contains 'update -y') 'codebase-memory-mcp updates should be non-interactive'
    Assert-True ($script:CodebaseMemoryInput -contains '1') 'codebase-memory-mcp should select the standard variant'
}

function test_installai_fails_when_codebase_memory_install_fails {
    $script:Dry = $false
    Set-FunctionMock 'InstallCodex' { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-RestMethod' { 'function global:codebase-memory-mcp { $global:LASTEXITCODE = 1 }; codebase-memory-mcp install' }

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

function test_installpi_updates_extensions_during_update {
    $script:PiCalls = @()
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return [pscustomobject]@{ Source = 'mock-pi' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'pi' {
        $script:PiCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    InstallPi -Update

    Assert-True ($script:PiCalls -contains 'update --extensions') 'Pi extensions should update during dotfile update'
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

function test_pi_subagents_package_routes_all_agents_to_luna_max {
    $path = Join-Path $script:RepoDir 'config\shared\ai\pi\settings.json'
    $settings = Get-Content -Raw $path | ConvertFrom-Json

    Assert-True (@($settings.packages) -contains 'npm:pi-subagents@0.40.0') 'Pi should install the pinned pi-subagents package'
    Assert-Equals 'gpt-5.6-sol' $settings.defaultModel
    Assert-Equals 'medium' $settings.defaultThinkingLevel
    Assert-Equals 'openai-codex/gpt-5.6-luna' $settings.subagents.defaultModel
    Assert-Equals 'max' $settings.subagents.defaultThinking

    foreach ($agent in 'advisor', 'context-builder', 'delegate', 'oracle', 'planner', 'researcher', 'reviewer', 'scout', 'worker') {
        $override = $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value
        Assert-Equals 'openai-codex/gpt-5.6-luna' $override.model
        Assert-Equals 'max' $override.thinking
    }
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
