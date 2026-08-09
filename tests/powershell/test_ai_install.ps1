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

function test_windows_codex_seed_contains_only_portable_state {
    $seed = Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\ai\codex\config.toml')

    foreach ($runtimeState in @(
            'C:\\Users\\',
            'notify =',
            '[marketplaces.openai-bundled]',
            '[marketplaces.openai-primary-runtime]',
            '[mcp_servers.node_repl]',
            '[projects.',
            'SKY_CUA_NATIVE_PIPE',
            'CODEX_CLI_PATH',
            '[shell_environment_policy.set]'
        )) {
        Assert-False ($seed.Contains($runtimeState)) "Codex seed should not track runtime state: $runtimeState"
    }
    foreach ($portableSetting in @(
            '[windows]',
            'sandbox = "elevated"',
            'network_access = false',
            '[mcp_servers.fff]',
            '[mcp_servers.codebase-memory-mcp]'
        )) {
        Assert-True ($seed.Contains($portableSetting)) "Codex seed should retain portable setting: $portableSetting"
    }
}

function test_synccodexconfig_does_not_apply_live_state_to_tracked_seed {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    'model = "tracked"' | Set-Content $source
    'model = "live"' | Set-Content $target
    $script:CodexApplyPath = $null

    Set-CommandMock 'py' {
        $script:CodexApplyPath = $args[-1]
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'jq' {
        $global:LASTEXITCODE = 0
        '{"model":"tracked"}'
    }

    SyncCodexConfig

    Assert-Equals '' $script:CodexApplyPath
    Assert-Equals 'model = "tracked"' ((Get-Content -Raw $source).Trim())
}

function test_installfffmcp_installs_verified_windows_binary_for_codex {
    $script:FffUrl = ''
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:FffUrl = $Uri
        'fff' | Set-Content -NoNewline $OutFile
    }
    Set-CommandMock 'Get-FileHash' {
        [pscustomobject]@{ Hash = 'e341b78464095c349b0c6b0a32b146fd217b542d973917b89645a5aa511640d8' }
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
    Assert-Contains (Get-Content -Raw $script:DotfileScript) 'config\shared\ai\skills\diff-review-qa'
    Assert-FileExists (Join-Path $env:USERPROFILE '.agents\skills\diff-review-qa\SKILL.md')
}

function test_installcodebasememory_skips_current_version {
    $script:Dry = $false
    $script:CodebaseInstallerDownloaded = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' {
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -eq '--version') { 'codebase-memory-mcp 0.9.0' }
    }
    Set-CommandMock 'Invoke-RestMethod' { [pscustomobject]@{ tag_name = 'v0.9.0' } }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:CodebaseInstallerDownloaded = $true
        '$global:LASTEXITCODE = 0' | Set-Content $OutFile
    }

    InstallCodebaseMemory -Update 6>&1 | Out-Null

    Assert-False $script:CodebaseInstallerDownloaded 'current codebase-memory-mcp should not be downloaded again'
}

function test_installcodebasememory_removes_legacy_executable {
    $script:Dry = $false
    $legacy = Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe'
    $installed = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path $legacy -Parent), (Split-Path $installed -Parent) | Out-Null
    'legacy' | Set-Content $legacy
    'installed' | Set-Content $installed
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = $installed } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' { $global:LASTEXITCODE = 0 }

    InstallCodebaseMemory 6>&1 | Out-Null

    Assert-False (Test-Path -LiteralPath $legacy) 'legacy codebase-memory-mcp executable should be removed'
    Assert-FileExists $installed
}

function test_installcodebasememory_updates_with_full_ui_installer {
    $script:Dry = $false
    $script:CodebaseInstallerArgsPath = Join-Path $env:USERPROFILE 'codebase-installer-args.txt'
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' {
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -eq '--version') { 'codebase-memory-mcp 0.8.0' }
    }
    Set-CommandMock 'Invoke-RestMethod' { [pscustomobject]@{ tag_name = 'v0.9.0' } }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        "Set-Content -Path '$script:CodebaseInstallerArgsPath' -Value (`$args -join ' '); `$global:LASTEXITCODE = 0" | Set-Content $OutFile
    }

    InstallCodebaseMemory -Update 6>&1 | Out-Null

    Assert-Contains (Get-Content -Raw $script:CodebaseInstallerArgsPath) '--ui'
}

function test_installcodebasememory_enables_automatic_indexing {
    $script:Dry = $false
    $script:CodebaseMemoryCalls = @()
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'mock-codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' {
        $script:CodebaseMemoryCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }

    InstallCodebaseMemory 6>&1 | Out-Null

    Assert-True ($script:CodebaseMemoryCalls -contains 'config set auto_index true') 'automatic indexing should be enabled'
    Assert-True ($script:CodebaseMemoryCalls -contains 'config set auto_watch true') 'automatic watching should be enabled'
}

function test_installcodebasememory_fails_when_installer_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-RestMethod' { [pscustomobject]@{ tag_name = 'v0.9.0' } }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        '$global:LASTEXITCODE = 1' | Set-Content $OutFile
    }

    Assert-Throws { InstallCodebaseMemory 6>&1 | Out-Null } 'InstallCodebaseMemory should fail when its installer fails'
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

function test_installpi_skips_current_package_during_update {
    $script:NpmCalls = @()
    $script:PiCalls = @()
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return [pscustomobject]@{ Source = 'mock-pi' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' {
        $call = $args -join ' '
        $script:NpmCalls += ,$call
        if ($call -eq 'view @earendil-works/pi-coding-agent version') { '0.84.0' }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'pi' {
        $call = $args -join ' '
        $script:PiCalls += ,$call
        if ($call -eq '--version') { '0.84.0' }
        $global:LASTEXITCODE = 0
    }

    InstallPi -Update

    Assert-False ($script:NpmCalls -contains 'install --global @earendil-works/pi-coding-agent') 'current Pi package should not reinstall'
    Assert-True ($script:PiCalls -contains 'update --extensions') 'Pi extensions should still update'
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

function test_pi_subagents_package_uses_model_tiers_and_provider_scope {
    $path = Join-Path $script:RepoDir 'config\shared\ai\pi\settings.json'
    $settings = Get-Content -Raw $path | ConvertFrom-Json

    Assert-True (@($settings.packages) -contains 'npm:pi-subagents@0.40.0') 'Pi should install the pinned pi-subagents package'
    Assert-Equals 'gpt-5.6-sol' $settings.defaultModel
    Assert-Equals 'high' $settings.defaultThinkingLevel
    Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.defaultModel
    Assert-Equals 'xhigh' $settings.subagents.defaultThinking
    Assert-True $settings.subagents.modelScope.enforce
    Assert-Equals 1 @($settings.subagents.modelScope.allow).Count
    Assert-Equals 'openai-codex/*' @($settings.subagents.modelScope.allow)[0]

    foreach ($agent in 'advisor', 'oracle') {
        $override = $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value
        Assert-Equals 'openai-codex/gpt-5.6-sol' $override.model
        Assert-Equals 'xhigh' $override.thinking
    }
    foreach ($agent in 'delegate', 'scout', 'worker') {
        $override = $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value
        Assert-Equals 'openai-codex/gpt-5.6-luna' $override.model
        Assert-Equals 'max' $override.thinking
    }
}

function test_pi_lsp_package_is_pinned {
    $path = Join-Path $script:RepoDir 'config\shared\ai\pi\settings.json'
    $settings = Get-Content -Raw $path | ConvertFrom-Json

    Assert-True (@($settings.packages) -contains 'npm:@narumitw/pi-lsp@0.49.4') 'Pi should install the pinned LSP package'
}

function test_syncpiconfigs_creates_writable_seed_files {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    '{"theme":"dark"}' | Set-Content (Join-Path $seedDir 'settings.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    'extension' | Set-Content (Join-Path $seedDir 'caveman-default.js')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    'extension' | Set-Content (Join-Path $seedDir 'windows-exit.js')

    SyncPiConfigs

    $settings = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $mcp = Join-Path $env:USERPROFILE '.pi\agent\mcp.json'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    Assert-FileExists $settings
    Assert-FileExists $mcp
    Assert-FileExists (Join-Path $extensionDir 'caveman-default.js')
    Assert-FileExists (Join-Path $extensionDir 'codex-status.js')
    Assert-FileExists (Join-Path $extensionDir 'windows-exit.js')
    Assert-False ([bool](Get-Item $settings).LinkType) 'Pi settings should stay writable'
}

function test_syncpiconfigs_replaces_stale_live_subagents {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $mergeDir = Join-Path $script:DotfilesDir 'scripts\seed_merge'
    $targetDir = Join-Path $env:USERPROFILE '.pi\agent'
    New-Item -ItemType Directory -Force -Path $seedDir, $mergeDir, $targetDir | Out-Null
    Copy-Item (Join-Path $script:RepoDir 'scripts\seed_merge\*') $mergeDir

    @'
{
  "theme": "dark",
  "subagents": {
    "defaultModel": "openai-codex/gpt-5.6-terra",
    "agentOverrides": {
      "worker": {"model": "openai-codex/gpt-5.6-luna"}
    }
  }
}
'@ | Set-Content (Join-Path $seedDir 'settings.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    'extension' | Set-Content (Join-Path $seedDir 'caveman-default.js')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    'extension' | Set-Content (Join-Path $seedDir 'windows-exit.js')
    @'
{
  "theme": "light",
  "runtimeOnly": true,
  "subagents": {
    "defaultModel": "openai-codex/gpt-5.6-luna",
    "agentOverrides": {
      "worker": {"model": "openai-codex/gpt-5.6-luna"},
      "reviewer": {"model": "openai-codex/gpt-5.6-luna"}
    }
  }
}
'@ | Set-Content (Join-Path $targetDir 'settings.json')

    $seed = Join-Path $seedDir 'settings.json'
    Set-CommandMock 'py' {
        $pythonArgs = @($args)
        & python3 @($pythonArgs[1..($pythonArgs.Count - 1)])
    }
    try {
        (Get-Item $seed).IsReadOnly = $true
        SyncPiConfigs

        $settings = Get-Content -Raw (Join-Path $targetDir 'settings.json') | ConvertFrom-Json
        Assert-Equals 'dark' $settings.theme
        Assert-True $settings.runtimeOnly 'Live-only unrelated settings should be preserved'
        Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.defaultModel
        Assert-False ($settings.subagents.agentOverrides.PSObject.Properties.Name -contains 'reviewer') 'Removed tracked subagent overrides should stay removed'
    } finally {
        (Get-Item $seed).IsReadOnly = $false
    }
}
