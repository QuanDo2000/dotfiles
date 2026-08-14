# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
    $releaseCheck = Get-Command Test-CodexRelease -ErrorAction SilentlyContinue
    $pathSetter = Get-Command Set-CodexActivePath -ErrorAction SilentlyContinue
    $codebaseReleaseCheck = Get-Command Test-CodebaseMemoryRelease -ErrorAction SilentlyContinue
    $codebasePathSetter = Get-Command Set-CodebaseMemoryActivePath -ErrorAction SilentlyContinue
    $codebaseInvoker = Get-Command Invoke-CodebaseMemoryCommand -ErrorAction SilentlyContinue
    $codebaseArchiveCheck = Get-Command Test-CodebaseMemoryArchive -ErrorAction SilentlyContinue
    $codebaseProcessStopper = Get-Command Stop-CodebaseMemoryProcesses -ErrorAction SilentlyContinue
    $codebaseConfigAccessTester = Get-Command Test-CodebaseMemoryConfigDatabaseAccess -ErrorAction SilentlyContinue
    $codebaseConfigRepairer = Get-Command Repair-CodebaseMemoryConfigDatabase -ErrorAction SilentlyContinue
    $script:OriginalTestCodexRelease = if ($releaseCheck) { $releaseCheck.ScriptBlock } else { $null }
    $script:OriginalSetCodexActivePath = if ($pathSetter) { $pathSetter.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryRelease = if ($codebaseReleaseCheck) { $codebaseReleaseCheck.ScriptBlock } else { $null }
    $script:OriginalSetCodebaseMemoryActivePath = if ($codebasePathSetter) { $codebasePathSetter.ScriptBlock } else { $null }
    $script:OriginalInvokeCodebaseMemoryCommand = if ($codebaseInvoker) { $codebaseInvoker.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryArchive = if ($codebaseArchiveCheck) { $codebaseArchiveCheck.ScriptBlock } else { $null }
    $script:OriginalStopCodebaseMemoryProcesses = if ($codebaseProcessStopper) { $codebaseProcessStopper.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryConfigDatabaseAccess = if ($codebaseConfigAccessTester) { $codebaseConfigAccessTester.ScriptBlock } else { $null }
    $script:OriginalRepairCodebaseMemoryConfigDatabase = if ($codebaseConfigRepairer) { $codebaseConfigRepairer.ScriptBlock } else { $null }
    $script:OriginalCodexHome = $env:CODEX_HOME
    Set-CommandMock 'RepairPiCompactionSteering' {}
    if ($script:OriginalStopCodebaseMemoryProcesses) { Set-FunctionMock 'Stop-CodebaseMemoryProcesses' {} }
}

function TestTeardown {
    foreach ($command in 'npm', 'npx', 'pi', 'py', 'jq', 'Get-Command', 'Get-FileHash', 'Get-Process', 'New-Item', 'Copy-Item', 'Expand-Archive', 'Move-Item', 'Start-Process', 'Stop-Process', 'Wait-Process', 'codebase-memory-mcp', 'irm', 'Invoke-RestMethod', 'Invoke-WebRequest', 'tar', 'vtsls', 'bash-language-server', 'shellcheck', 'RepairPiCompactionSteering') {
        Clear-CommandMock $command
    }
    Set-FunctionMock 'InstallCodex' $script:OriginalInstallCodex
    Set-FunctionMock 'AddToUserPath' $script:OriginalAddToUserPath
    if ($script:OriginalTestCodexRelease) { Set-FunctionMock 'Test-CodexRelease' $script:OriginalTestCodexRelease }
    if ($script:OriginalSetCodexActivePath) { Set-FunctionMock 'Set-CodexActivePath' $script:OriginalSetCodexActivePath }
    if ($script:OriginalTestCodebaseMemoryRelease) { Set-FunctionMock 'Test-CodebaseMemoryRelease' $script:OriginalTestCodebaseMemoryRelease }
    if ($script:OriginalSetCodebaseMemoryActivePath) { Set-FunctionMock 'Set-CodebaseMemoryActivePath' $script:OriginalSetCodebaseMemoryActivePath }
    if ($script:OriginalInvokeCodebaseMemoryCommand) { Set-FunctionMock 'Invoke-CodebaseMemoryCommand' $script:OriginalInvokeCodebaseMemoryCommand }
    if ($script:OriginalTestCodebaseMemoryArchive) { Set-FunctionMock 'Test-CodebaseMemoryArchive' $script:OriginalTestCodebaseMemoryArchive }
    if ($script:OriginalStopCodebaseMemoryProcesses) { Set-FunctionMock 'Stop-CodebaseMemoryProcesses' $script:OriginalStopCodebaseMemoryProcesses }
    if ($script:OriginalTestCodebaseMemoryConfigDatabaseAccess) { Set-FunctionMock 'Test-CodebaseMemoryConfigDatabaseAccess' $script:OriginalTestCodebaseMemoryConfigDatabaseAccess }
    if ($script:OriginalRepairCodebaseMemoryConfigDatabase) { Set-FunctionMock 'Repair-CodebaseMemoryConfigDatabase' $script:OriginalRepairCodebaseMemoryConfigDatabase }
    if ($null -eq $script:OriginalCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $script:OriginalCodexHome }
    Remove-Variable -Name PiInstalled -Scope Script -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function Get-TestSha256($Text) {
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Write-TestCodexPins($Version = '1.2.3', $X64Hash = ('a' * 64), $Arm64Hash = ('b' * 64)) {
    $pinsPath = Join-Path $script:DotfilesDir 'packages\codex-release.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $pinsPath -Parent) | Out-Null
    @{ version = $Version; linuxHash = 'sha256-linux'; darwinHash = 'sha256-darwin'; windows = @{ x86_64 = $X64Hash; aarch64 = $Arm64Hash } } |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $pinsPath -Encoding utf8
}

function Write-TestCodebaseMemoryPins($Version = '1.2.3', $Amd64Hash = ('c' * 64), $Arm64Hash = ('d' * 64)) {
    $pinsPath = Join-Path $script:DotfilesDir 'packages\codebase-memory-mcp-release.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $pinsPath -Parent) | Out-Null
    @{
        version = $Version
        linux = @{ amd64 = @{ file = 'codebase-memory-mcp-linux-amd64.tar.gz'; nixHash = 'sha256-linux'; sha256 = '1' * 64 } }
        darwin = @{ arm64 = @{ file = 'codebase-memory-mcp-darwin-arm64.tar.gz'; nixHash = 'sha256-darwin'; sha256 = '2' * 64 } }
        windows = @{
            amd64 = @{ file = 'codebase-memory-mcp-windows-amd64.zip'; sha256 = $Amd64Hash }
            arm64 = @{ file = 'codebase-memory-mcp-windows-arm64.zip'; sha256 = $Arm64Hash }
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $pinsPath -Encoding utf8
}

function test_windows_codebase_memory_uses_pinned_release_packages {
    $text = Get-Content -Raw $script:DotfileScript
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\codebase-memory-mcp-release.json') | ConvertFrom-Json
    $nixPackage = Get-Content -Raw (Join-Path $script:RepoDir 'packages\codebase-memory-mcp.nix')

    Assert-False ($text -like '*codebase-memory-mcp/$releaseTag/install.ps1*') 'remote codebase-memory installer should not execute'
    Assert-False ($text -like '*releases/latest*codebase-memory*') 'Windows codebase-memory release should not float'
    Assert-True ($pins.version -match '^\d+\.\d+\.\d+$') 'version should be exact semver'
    Assert-True ($pins.windows.amd64.sha256 -match '^[0-9a-f]{64}$') 'amd64 hash should be pinned'
    Assert-True ($pins.windows.arm64.sha256 -match '^[0-9a-f]{64}$') 'arm64 hash should be pinned'
    Assert-True ($pins.windows.amd64.file -match '^codebase-memory-mcp(?:-ui)?-windows-amd64.*\.zip$') 'amd64 file should be pinned'
    Assert-Contains $nixPackage 'codebase-memory-mcp-release.json'
    Assert-Contains $nixPackage '${source.file}'
}

function test_getcodebasememoryversion_requires_exact_semver_token {
    Assert-Equals '0.9.0' (Get-CodebaseMemoryVersionFromOutput 'codebase-memory-mcp 0.9.0')
    Assert-Equals '' (Get-CodebaseMemoryVersionFromOutput 'codebase-memory-mcp 0.9.0.1')
}

function test_getcodebasememorywindowsarch_supports_x64_and_arm64 {
    Assert-Equals 'amd64' (Get-CodebaseMemoryWindowsArch 'X64')
    Assert-Equals 'arm64' (Get-CodebaseMemoryWindowsArch 'Arm64')
    Assert-Throws { Get-CodebaseMemoryWindowsArch 'X86' } '32-bit Windows should be rejected'
}

function test_codebasememory_archive_rejects_unexpected_members {
    $source = Join-Path $script:_TestTmp.FullName 'codebase-archive-source'
    $archive = Join-Path $script:_TestTmp.FullName 'codebase-archive.zip'
    New-Item -ItemType Directory -Force -Path $source | Out-Null
    foreach ($name in 'codebase-memory-mcp.exe', 'LICENSE', 'install.ps1', 'THIRD_PARTY_NOTICES.md', 'unexpected.ps1') {
        [IO.File]::WriteAllText((Join-Path $source $name), $name)
    }
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $archive

    Assert-False (Test-CodebaseMemoryArchive $archive) 'unexpected archive member should fail closed'
}

function test_codebasememory_expands_locked_zip_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { return }

    $source = Join-Path $script:_TestTmp.FullName 'codebase-zip-source'
    $archive = Join-Path $script:_TestTmp.FullName 'codebase-package.zip'
    $destination = Join-Path $script:_TestTmp.FullName 'codebase-package-extracted'
    New-Item -ItemType Directory -Force -Path $source, $destination | Out-Null
    foreach ($name in 'codebase-memory-mcp.exe', 'LICENSE', 'install.ps1', 'THIRD_PARTY_NOTICES.md') {
        [IO.File]::WriteAllText((Join-Path $source $name), $name)
    }
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $archive
    $oldArchive = $env:CODEBASE_TEST_ARCHIVE
    $oldDestination = $env:CODEBASE_TEST_DESTINATION
    $env:CODEBASE_TEST_ARCHIVE = $archive
    $env:CODEBASE_TEST_DESTINATION = $destination
    $probe = @'
$ErrorActionPreference = 'Stop'
$lock = [IO.File]::Open($env:CODEBASE_TEST_ARCHIVE, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    Expand-Archive -LiteralPath $env:CODEBASE_TEST_ARCHIVE -DestinationPath $env:CODEBASE_TEST_DESTINATION -Force
} finally {
    $lock.Dispose()
}
if (-not (Test-Path -LiteralPath (Join-Path $env:CODEBASE_TEST_DESTINATION 'codebase-memory-mcp.exe'))) { exit 1 }
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))

    try {
        & $windowsPowerShell.Source -NoProfile -NonInteractive -EncodedCommand $encoded
        Assert-Equals 0 $LASTEXITCODE
    } finally {
        $env:CODEBASE_TEST_ARCHIVE = $oldArchive
        $env:CODEBASE_TEST_DESTINATION = $oldDestination
    }
}

function test_getcodebasememorypathvalue_replaces_legacy_and_managed_paths {
    $root = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp'
    $releases = Join-Path $root 'releases'
    $current = Join-Path $releases 'new-release'
    $old = "$(Join-Path $releases 'old-release');C:\Tools;$root"

    Assert-Equals "$current;C:\Tools" (Get-CodebaseMemoryPathValue $old $current $releases $root)
}

function test_windows_codex_uses_pinned_release_packages {
    $text = Get-Content -Raw $script:DotfileScript
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\codex-release.json') | ConvertFrom-Json

    Assert-False ($text -like '*https://chatgpt.com/codex/install.ps1*') 'mutable Codex installer should not execute'
    Assert-False ($text -like '*Invoke-RestMethod https://chatgpt.com/codex/install.ps1*') 'remote Codex script should not be piped to execution'
    Assert-Equals '0.147.0' $pins.version
    Assert-Equals 'c156c8feb8cb20197bf74d2c6daffed1fec0a8c21a03bc2ca90d7ff81927b0c5' $pins.windows.x86_64
    Assert-Equals '4533928d72ac4d7c19f16e8c4acdfd02dc255d2aeeb2f6d7dfd45493ec4c0806' $pins.windows.aarch64
    Assert-Contains $text 'codex-package-$target.tar.gz'
}

function test_getcodexwindowstarget_supports_x64_and_arm64 {
    Assert-Equals 'x86_64-pc-windows-msvc' (Get-CodexWindowsTarget 'X64')
    Assert-Equals 'aarch64-pc-windows-msvc' (Get-CodexWindowsTarget 'Arm64')
    Assert-Throws { Get-CodexWindowsTarget 'X86' } '32-bit Windows should be rejected'
}

function test_setcodexactivepath_preserves_current_process_path {
    $script:Dry = $false
    $oldUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $oldProcessPath = $env:Path
    try {
        Set-CodexActivePath 'C:\Codex\new\bin' 'C:\Codex\releases'
        Assert-Equals $oldProcessPath $env:Path
    } finally {
        [Environment]::SetEnvironmentVariable('Path', $oldUserPath, 'User')
        $env:Path = $oldProcessPath
    }
}

function test_getcodexpathvalue_prepends_release_and_removes_old_managed_paths {
    $managedRoot = 'C:\Users\test\.codex\packages\standalone\releases'
    $legacyBin = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin'
    $old = "$managedRoot\old\bin;C:\Tools;$legacyBin"
    $current = "$managedRoot\new\bin"

    $result = Get-CodexPathValue $old $current $managedRoot

    Assert-Equals "$current;C:\Tools" $result
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
            '[marketplaces.ponytail]',
            '[plugins."ponytail@ponytail"]',
            'source_type = "git"',
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
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\fff-release.json') | ConvertFrom-Json
    $script:FffUrl = ''
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:FffUrl = $Uri
        'fff' | Set-Content -NoNewline $OutFile
    }
    Set-CommandMock 'Get-FileHash' {
        [pscustomobject]@{ Hash = $pins.mcp.'windows-x64'.sha256 }
    }
    Set-FunctionMock 'AddToUserPath' { }

    InstallFffMcp

    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    $launcher = Join-Path $binDir 'fff-mcp-agent.cmd'
    Assert-FileExists (Join-Path $binDir 'fff-mcp.exe')
    Assert-FileExists $launcher
    Assert-Contains (Get-Content -Raw $launcher) '--frecency-db "%LOCALAPPDATA%\fff\frecency"'
    Assert-False ((Get-Content -Raw $launcher) -like '*--history-db*') 'native MCP history is unsupported and should not be configured'
    Assert-Contains $script:FffUrl "/v$($pins.version)/$($pins.mcp.'windows-x64'.file)"
    $codex = Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\ai\codex\config.toml')
    Assert-Contains $codex 'command = "cmd.exe"'
    Assert-Contains $codex '"fff-mcp-agent.cmd"'
}

function test_installfffmcp_stops_running_server_before_update {
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\fff-release.json') | ConvertFrom-Json
    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    'old' | Set-Content -NoNewline (Join-Path $binDir 'fff-mcp.exe')
    $script:FffProcessesStopped = $false
    Set-CommandMock 'Get-Process' { [pscustomobject]@{ ProcessName = 'fff-mcp' } }
    Set-CommandMock 'Stop-Process' { $script:FffProcessesStopped = $true }
    Set-CommandMock 'Wait-Process' { }
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        if (Test-Path -LiteralPath $Destination) { throw 'Cannot create a file when that file already exists.' }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        'new' | Set-Content -NoNewline $OutFile
    }
    Set-CommandMock 'Get-FileHash' {
        [pscustomobject]@{ Hash = $pins.mcp.'windows-x64'.sha256 }
    }
    Set-FunctionMock 'AddToUserPath' { }

    InstallFffMcp -Update

    Assert-True $script:FffProcessesStopped 'running FFF MCP server should stop before replacing its executable'
    Assert-Equals 'new' (Get-Content -Raw (Join-Path $binDir 'fff-mcp.exe'))
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

function test_install_skill_directory_rejects_linked_source_root {
    $realSource = Join-Path $script:_TestTmp.FullName 'real-source-skill'
    $linkedSource = Join-Path $script:_TestTmp.FullName 'linked-source-skill'
    $target = Join-Path $script:_TestTmp.FullName 'target-skill'
    New-Item -ItemType Directory -Force -Path $realSource, $target | Out-Null
    'new' | Set-Content (Join-Path $realSource 'SKILL.md')
    'old' | Set-Content (Join-Path $target 'SKILL.md')
    $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $linkedSource -Target $realSource | Out-Null

    Assert-Throws { Install-SkillDirectory $linkedSource $target } 'linked source root should fail closed'
    Assert-Contains (Get-Content -Raw (Join-Path $target 'SKILL.md')) 'old'
}

function test_install_skill_directory_rejects_linked_skill_file {
    $source = Join-Path $script:_TestTmp.FullName 'source-skill'
    $external = Join-Path $script:_TestTmp.FullName 'external-SKILL.md'
    $target = Join-Path $script:_TestTmp.FullName 'target-skill'
    New-Item -ItemType Directory -Force -Path $source, $target | Out-Null
    'external' | Set-Content $external
    'old' | Set-Content (Join-Path $target 'SKILL.md')
    New-Item -ItemType SymbolicLink -Path (Join-Path $source 'SKILL.md') -Target $external | Out-Null

    Assert-Throws { Install-SkillDirectory $source $target } 'linked SKILL.md should fail closed'
    Assert-Contains (Get-Content -Raw (Join-Path $target 'SKILL.md')) 'old'
}

function test_install_skill_directory_preserves_current_copy_when_staging_fails {
    $source = Join-Path $script:_TestTmp.FullName 'source-skill'
    $target = Join-Path $script:_TestTmp.FullName 'target-skill'
    New-Item -ItemType Directory -Force -Path $source, $target | Out-Null
    'new' | Set-Content (Join-Path $source 'SKILL.md')
    'old' | Set-Content (Join-Path $target 'SKILL.md')
    Set-CommandMock 'Copy-Item' { throw 'copy failed' }

    Assert-Throws { Install-SkillDirectory $source $target } 'staging copy failure should surface'
    Assert-Contains (Get-Content -Raw (Join-Path $target 'SKILL.md')) 'old'
}

function test_installai_skills_copies_only_vendored_shared_skills {
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $sourceRoot = Join-Path $script:DotfilesDir 'config\shared\ai\skills'
    $targetRoot = Join-Path $env:USERPROFILE '.agents\skills'
    $skills = @('caveman', 'systematic-debugging', 'test-driven-development', 'verification-before-completion', 'diff-review-qa', 'ponytail', 'ponytail-audit', 'ponytail-debt', 'ponytail-gain', 'ponytail-help', 'ponytail-review')
    foreach ($skill in $skills) {
        $source = Join-Path $sourceRoot $skill
        $target = Join-Path $targetRoot $skill
        New-Item -ItemType Directory -Force -Path (Join-Path $source 'references'), $target | Out-Null
        "vendored $skill" | Set-Content (Join-Path $source 'SKILL.md')
        'relative file' | Set-Content (Join-Path $source 'references\details.md')
        'stale' | Set-Content (Join-Path $target 'stale.md')
    }
    foreach ($skill in $skills) {
        New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill") | Out-Null
    }
    Set-CommandMock 'npx' { throw 'npx must not install shared skills' }

    InstallAiSkills

    foreach ($skill in $skills) {
        $target = Join-Path $targetRoot $skill
        Assert-Contains (Get-Content -Raw (Join-Path $target 'SKILL.md')) "vendored $skill"
        Assert-FileExists (Join-Path $target 'references\details.md')
        Assert-False (Test-Path (Join-Path $target 'stale.md')) "Stale shared skill file remains for $skill"
    }
    foreach ($skill in $skills) {
        Assert-False (Test-Path (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill")) "Stale Pi copy remains for $skill"
    }
}

function Get-TestCodebaseMemoryCodexHookBlock {
    @'
# >>> codebase-memory-mcp SessionStart >>>
[[hooks.SessionStart]]
matcher = "startup|resume|clear|compact"

[[hooks.SessionStart.hooks]]
type = "command"
command = "codebase-memory-mcp hook-augment"
# <<< codebase-memory-mcp SessionStart <<<
'@
}

function test_repaircodebasememorycodexhooks_removes_marker_conflicting_with_inline_hooks {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    "[hooks]`nSessionStart = []`n`n$(Get-TestCodebaseMemoryCodexHookBlock)" | Set-Content -LiteralPath $config

    Repair-CodebaseMemoryCodexHooks $config

    $actual = Get-Content -Raw -LiteralPath $config
    Assert-True ($actual.Contains('SessionStart = []')) 'inline hook should remain'
    Assert-False ($actual.Contains('# >>> codebase-memory-mcp SessionStart >>>')) 'conflicting managed hook should be removed'
}

function test_repaircodebasememorycodexmcp_wraps_owned_section_before_tool_approvals {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    @'
[mcp_servers.codebase-memory-mcp]
command = "C:/Users/test/.local/bin/codebase-memory-mcp.exe"

[mcp_servers.codebase-memory-mcp.tools.search_graph]
approval_mode = "approve"
'@ | Set-Content -LiteralPath $config

    Repair-CodebaseMemoryCodexMcp $config

    $actual = Get-Content -Raw -LiteralPath $config
    Assert-Contains $actual '# >>> codebase-memory-mcp MCP >>>'
    Assert-Contains $actual '# <<< codebase-memory-mcp MCP <<<'
    Assert-True ($actual.Contains('[mcp_servers.codebase-memory-mcp.tools.search_graph]')) 'tool approval table should remain'
}

function test_repaircodebasememorycodexhooks_preserves_nonconflicting_marker {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    Get-TestCodebaseMemoryCodexHookBlock | Set-Content -LiteralPath $config

    Repair-CodebaseMemoryCodexHooks $config

    Assert-Contains (Get-Content -Raw -LiteralPath $config) '# >>> codebase-memory-mcp SessionStart >>>'
}

function test_linktargetexists_resolves_relative_target_from_link_parent {
    $link = Join-Path $env:USERPROFILE 'links\config.json'
    $target = Join-Path $env:USERPROFILE 'links\targets\config.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    '{}' | Set-Content -LiteralPath $target

    Assert-True (Test-LinkTargetExists $link 'targets\config.json') 'relative link target should resolve from link parent'
}

function test_removedanglinglink_removes_reparse_point_with_missing_target {
    $target = Join-Path $env:USERPROFILE 'missing-target'
    $link = Join-Path $env:USERPROFILE 'stale-link'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Remove-Item -LiteralPath $target -Force

    Remove-DanglingLink $link

    Assert-False ([bool](Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue)) 'dangling link should be removed'
}

function test_invokecodebasememoryagentinstall_restores_approvals_when_repair_fails {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    @'
[mcp_servers.codebase-memory-mcp]
command = "C:/Users/test/.local/bin/codebase-memory-mcp.exe"

[mcp_servers.codebase-memory-mcp.tools.search_graph]
approval_mode = "approve"
'@ | Set-Content -LiteralPath $config
    $originalRepair = (Get-Command Repair-CodebaseMemoryCodexMcp).ScriptBlock
    Set-FunctionMock 'Repair-CodebaseMemoryCodexMcp' { throw 'repair failed' }
    try {
        Assert-Throws { Invoke-CodebaseMemoryAgentInstall 'codebase-memory-mcp.exe' }
    } finally {
        Set-FunctionMock 'Repair-CodebaseMemoryCodexMcp' $originalRepair
    }

    Assert-True ((Get-Content -Raw -LiteralPath $config).Contains('[mcp_servers.codebase-memory-mcp.tools.search_graph]')) 'tool approvals should survive pre-install repair failure'
}

function test_invokecodebasememoryagentinstall_repairs_hook_conflict_created_by_installer {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    "[hooks]`nSessionStart = []`n" | Set-Content -LiteralPath $config
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        Add-Content -LiteralPath $config -Value (Get-TestCodebaseMemoryCodexHookBlock)
    }

    Invoke-CodebaseMemoryAgentInstall 'codebase-memory-mcp.exe'

    $actual = Get-Content -Raw -LiteralPath $config
    Assert-True ($actual.Contains('SessionStart = []')) 'inline hook should remain'
    Assert-False ($actual.Contains('# >>> codebase-memory-mcp SessionStart >>>')) 'installer-created hook conflict should be repaired'
}

function test_invokecodebasememoryagentinstall_temporarily_removes_tool_approvals {
    $config = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $config -Parent) | Out-Null
    @'
[mcp_servers.codebase-memory-mcp]
command = "C:/Users/test/.local/bin/codebase-memory-mcp.exe"

[mcp_servers.codebase-memory-mcp.tools.search_graph]
approval_mode = "approve"
'@ | Set-Content -LiteralPath $config
    $script:ToolApprovalsPresentDuringInstall = $null
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        $script:ToolApprovalsPresentDuringInstall = (Get-Content -Raw -LiteralPath $config).Contains('.tools.search_graph]')
    }

    Invoke-CodebaseMemoryAgentInstall 'codebase-memory-mcp.exe'

    Assert-False $script:ToolApprovalsPresentDuringInstall 'tool approval tables should be absent while CBM edits its MCP block'
    Assert-True ((Get-Content -Raw -LiteralPath $config).Contains('[mcp_servers.codebase-memory-mcp.tools.search_graph]')) 'tool approval tables should be restored'
}

function test_repaircodebasememoryskill_ignores_description_in_markdown_body {
    $skill = Join-Path $env:USERPROFILE '.agents\skills\codebase-memory\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path $skill -Parent) | Out-Null
    "---`nname: codebase-memory`n---`n`ndescription: body: text" | Set-Content -LiteralPath $skill

    Repair-CodebaseMemorySkill $skill

    Assert-Contains (Get-Content -Raw -LiteralPath $skill) 'description: body: text'
}

function test_repaircodebasememoryskill_quotes_yaml_description {
    $skill = Join-Path $env:USERPROFILE '.agents\skills\codebase-memory\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path $skill -Parent) | Out-Null
    "---`nname: codebase-memory`ndescription: Use graph. Triggers on: architecture`n---`n`n# Codebase Memory" | Set-Content -LiteralPath $skill

    Repair-CodebaseMemorySkill $skill

    Assert-Contains (Get-Content -Raw -LiteralPath $skill) "description: 'Use graph. Triggers on: architecture'"
}

function test_removecodebasememorypiskill_removes_only_generated_skill {
    $generated = Join-Path $env:USERPROFILE '.pi\agent\skills\codebase-memory'
    $custom = Join-Path $env:USERPROFILE '.pi\agent\skills\custom-codebase-memory'
    New-Item -ItemType Directory -Force -Path $generated, $custom | Out-Null
    "---`nname: codebase-memory`n---`n# Codebase Memory — Knowledge Graph Tools`n## 15 MCP Tools" | Set-Content -LiteralPath (Join-Path $generated 'SKILL.md')
    "---`nname: codebase-memory`n---`n# Custom" | Set-Content -LiteralPath (Join-Path $custom 'SKILL.md')

    Remove-CodebaseMemoryPiSkill $generated
    Remove-CodebaseMemoryPiSkill $custom

    Assert-False (Test-Path -LiteralPath $generated) 'generated duplicate Pi skill should be removed'
    Assert-FileExists (Join-Path $custom 'SKILL.md')
}

function test_invokecodebasememoryagentinstall_removes_generated_pi_adapter {
    $adapter = Join-Path $env:USERPROFILE '.pi\agent\extensions\cbmem.ts'
    New-Item -ItemType Directory -Force -Path (Split-Path $adapter -Parent) | Out-Null
    "// codebase-memory-mcp:start`n// Generated by codebase-memory-mcp for pi.`n// codebase-memory-mcp:end" | Set-Content -LiteralPath $adapter
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' { }

    Invoke-CodebaseMemoryAgentInstall 'codebase-memory-mcp.exe'

    Assert-False (Test-Path -LiteralPath $adapter) 'generated Pi adapter should be removed'
}

function test_removecodebasememorypiadapter_preserves_user_owned_extension {
    $adapter = Join-Path $env:USERPROFILE '.pi\agent\extensions\cbmem.ts'
    New-Item -ItemType Directory -Force -Path (Split-Path $adapter -Parent) | Out-Null
    'export default function custom() {}' | Set-Content -LiteralPath $adapter

    Remove-CodebaseMemoryPiAdapter $adapter

    Assert-FileExists $adapter
}

function test_repaircodebasememoryconfigdatabase_elevates_acl_repair {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }

    $database = "$env:USERPROFILE/.cache/codebase-memory-mcp/_config.db"
    $normalizedDatabase = [IO.Path]::GetFullPath($database)
    $script:CodebaseMemoryAccessChecks = 0
    $script:CodebaseMemoryRepairArgs = @()
    $script:CodebaseMemoryRepairVerb = ''
    Set-FunctionMock 'Test-CodebaseMemoryConfigDatabaseAccess' {
        $script:CodebaseMemoryAccessChecks++
        return ($script:CodebaseMemoryAccessChecks -gt 1)
    }
    Set-CommandMock 'Start-Process' {
        param($FilePath, $ArgumentList, $Verb, [switch]$Wait, [switch]$PassThru)
        $script:CodebaseMemoryRepairArgs = @($ArgumentList)
        $script:CodebaseMemoryRepairVerb = $Verb
        [pscustomobject]@{ ExitCode = 0 }
    }

    Repair-CodebaseMemoryConfigDatabase $database

    $encodedIndex = [Array]::IndexOf($script:CodebaseMemoryRepairArgs, '-EncodedCommand')
    $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:CodebaseMemoryRepairArgs[$encodedIndex + 1]))
    Assert-Equals 2 $script:CodebaseMemoryAccessChecks
    Assert-Equals 'RunAs' $script:CodebaseMemoryRepairVerb
    Assert-Contains $command 'takeown.exe'
    Assert-Contains $command 'icacls.exe'
    Assert-Contains $command $normalizedDatabase
}

function test_installcodebasememory_skips_current_pinned_release {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $release = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-cccccccccccc'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    $script:CodebaseInstallerDownloaded = $false
    Set-CommandMock 'Invoke-WebRequest' { $script:CodebaseInstallerDownloaded = $true }
    Set-FunctionMock 'Test-CodebaseMemoryRelease' { $true }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' { }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' { }

    InstallCodebaseMemory -Update 6>&1 | Out-Null

    Assert-False $script:CodebaseInstallerDownloaded 'current pinned codebase-memory release should not download again'
}

function test_installcodebasememory_keeps_published_executable_used_by_agent_configs {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $release = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-cccccccccccc'
    $legacy = Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe'
    New-Item -ItemType Directory -Force -Path $release, (Split-Path $legacy -Parent) | Out-Null
    'legacy' | Set-Content $legacy
    Set-FunctionMock 'Test-CodebaseMemoryRelease' { $true }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' { }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' { }

    InstallCodebaseMemory 6>&1 | Out-Null

    Assert-FileExists $legacy
    Assert-FileExists $release
}

function test_installcodebasememory_does_not_activate_when_agent_configuration_fails {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $release = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-cccccccccccc'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    $script:CodebaseMemoryActivated = $false
    Set-FunctionMock 'Test-CodebaseMemoryRelease' { $true }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' { $script:CodebaseMemoryActivated = $true }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        if (($Arguments -join ' ') -eq 'install -y') { throw 'agent configuration failed' }
    }

    Assert-Throws { InstallCodebaseMemory 6>&1 | Out-Null } 'agent configuration failure should surface'
    Assert-False $script:CodebaseMemoryActivated 'failed agent configuration should not activate release'
}

function test_installcodebasememory_does_not_activate_when_runtime_configuration_fails {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $release = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-cccccccccccc'
    New-Item -ItemType Directory -Force -Path $release | Out-Null
    $script:CodebaseMemoryActivated = $false
    Set-FunctionMock 'Test-CodebaseMemoryRelease' { $true }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' { $script:CodebaseMemoryActivated = $true }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        if (($Arguments -join ' ') -eq 'config set auto_index true') { throw 'runtime configuration failed' }
    }

    Assert-Throws { InstallCodebaseMemory 6>&1 | Out-Null } 'runtime configuration failure should surface'
    Assert-False $script:CodebaseMemoryActivated 'failed runtime configuration should not activate release'
}

function test_installcodebasememory_stages_verified_ui_archive_and_configures_direct_binary {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $archiveHash = Get-TestSha256 'archive'
    Write-TestCodebaseMemoryPins -Amd64Hash $archiveHash
    $script:CodebaseMemoryCalls = @()
    $script:ActivatedCodebaseMemoryDir = $null
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:CodebaseMemoryCalls += "download:$Uri"
        [IO.File]::WriteAllText($OutFile, 'archive')
    }
    Set-FunctionMock 'Test-CodebaseMemoryArchive' { $true }
    Set-CommandMock 'Expand-Archive' {
        param($LiteralPath, $DestinationPath, [switch]$Force)
        $script:CodebaseMemoryCalls += "extract:${LiteralPath}:$DestinationPath"
    }
    Set-FunctionMock 'Test-CodebaseMemoryRelease' {
        param($ReleaseDir, $ExpectedVersion)
        $script:CodebaseMemoryCalls += "verify:$ReleaseDir"
        $true
    }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' {
        param($ReleaseDir, $ReleasesRoot, $LegacyRoot)
        $script:ActivatedCodebaseMemoryDir = $ReleaseDir
        $script:CodebaseMemoryCalls += "activate:$ReleaseDir"
    }
    Set-FunctionMock 'Stop-CodebaseMemoryProcesses' {
        $script:CodebaseMemoryCalls += 'stop:processes'
    }
    Set-FunctionMock 'Repair-CodebaseMemoryConfigDatabase' {
        $script:CodebaseMemoryCalls += 'repair:config-database'
    }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        $script:CodebaseMemoryCalls += "run:${Executable}:$($Arguments -join ' ')"
    }

    InstallCodebaseMemory -Update 6>&1 | Out-Null

    $release = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-$($archiveHash.Substring(0, 12))"
    $executable = Join-Path $release 'codebase-memory-mcp.exe'
    Assert-FileExists $release
    Assert-Equals $release $script:ActivatedCodebaseMemoryDir
    $calls = $script:CodebaseMemoryCalls -join "`n"
    Assert-Contains $calls 'download:https://github.com/DeusData/codebase-memory-mcp/releases/download/v1.2.3/codebase-memory-mcp-windows-amd64.zip'
    Assert-Contains $calls "run:${executable}:install -y"
    Assert-Contains $calls 'stop:processes'
    Assert-Contains $calls 'repair:config-database'
    Assert-Contains $calls "run:${executable}:config set auto_index true"
    Assert-Contains $calls "run:${executable}:config set auto_watch true"
    $finalVerification = [Array]::IndexOf($script:CodebaseMemoryCalls, "verify:$release")
    $processStop = [Array]::IndexOf($script:CodebaseMemoryCalls, 'stop:processes')
    $databaseRepair = [Array]::IndexOf($script:CodebaseMemoryCalls, 'repair:config-database')
    $firstConfiguration = [Array]::IndexOf($script:CodebaseMemoryCalls, "run:${executable}:config set auto_index true")
    $lastConfiguration = [Array]::IndexOf($script:CodebaseMemoryCalls, "run:${executable}:config set auto_watch true")
    $activation = [Array]::IndexOf($script:CodebaseMemoryCalls, "activate:$release")
    Assert-True ($finalVerification -ge 0 -and $finalVerification -lt $processStop -and $processStop -lt $databaseRepair -and $databaseRepair -lt $firstConfiguration -and $firstConfiguration -le $lastConfiguration -and $lastConfiguration -lt $activation) 'release should verify, stop stale processes, repair config access, configure, then activate PATH'
}

function test_installcodebasememory_rejects_checksum_mismatch_before_extraction {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $script:CodebaseExpandCalled = $false
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        [IO.File]::WriteAllText($OutFile, 'wrong archive')
    }
    Set-CommandMock 'Expand-Archive' { $script:CodebaseExpandCalled = $true }

    Assert-Throws { InstallCodebaseMemory 6>&1 | Out-Null } 'codebase-memory checksum mismatch should fail'
    Assert-False $script:CodebaseExpandCalled 'unverified codebase-memory archive should not extract'
}

function test_codex_tar_extracts_locked_archive_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $tarCommand = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell -or -not $tarCommand) { return }

    $source = Join-Path $script:_TestTmp.FullName 'codex-package-source'
    $archive = Join-Path $script:_TestTmp.FullName 'codex-package.tar.gz'
    $destination = Join-Path $script:_TestTmp.FullName 'codex-package-extracted'
    foreach ($relativePath in 'codex-package.json', 'bin\codex.exe', 'bin\codex-code-mode-host.exe', 'codex-path\rg.exe', 'codex-resources\codex-command-runner.exe', 'codex-resources\codex-windows-sandbox-setup.exe') {
        $path = Join-Path $source $relativePath
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        [IO.File]::WriteAllText($path, $relativePath)
    }
    & $tarCommand.Source -czf $archive -C $source .
    Assert-Equals 0 $LASTEXITCODE
    New-Item -ItemType Directory -Force -Path $destination | Out-Null

    $oldArchive = $env:CODEX_TEST_ARCHIVE
    $oldDestination = $env:CODEX_TEST_DESTINATION
    $env:CODEX_TEST_ARCHIVE = $archive
    $env:CODEX_TEST_DESTINATION = $destination
    $probe = @'
$ErrorActionPreference = 'Stop'
$lock = [IO.File]::Open($env:CODEX_TEST_ARCHIVE, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    tar.exe -xzf $env:CODEX_TEST_ARCHIVE -C $env:CODEX_TEST_DESTINATION
    if ($LASTEXITCODE -ne 0) { exit 1 }
} finally {
    $lock.Dispose()
}
if (-not (Test-Path -LiteralPath (Join-Path $env:CODEX_TEST_DESTINATION 'codex-resources\codex-windows-sandbox-setup.exe'))) { exit 2 }
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))

    try {
        & $windowsPowerShell.Source -NoProfile -NonInteractive -EncodedCommand $encoded
        Assert-Equals 0 $LASTEXITCODE
    } finally {
        $env:CODEX_TEST_ARCHIVE = $oldArchive
        $env:CODEX_TEST_DESTINATION = $oldDestination
    }
}

function test_installcodex_rejects_checksum_mismatch_before_extraction {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $env:CODEX_HOME = Join-Path $script:_TestTmp.FullName 'codex-home'
    Write-TestCodexPins
    $script:CodexTarCalled = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'tar') { return [pscustomobject]@{ Source = 'mock-tar' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        [IO.File]::WriteAllText($OutFile, 'wrong archive')
    }
    Set-CommandMock 'tar' { $script:CodexTarCalled = $true; $global:LASTEXITCODE = 0 }

    Assert-Throws { InstallCodex 6>&1 | Out-Null } 'Codex archive checksum mismatch should fail'
    Assert-False $script:CodexTarCalled 'unverified Codex archive should not be extracted'
}

function test_installcodex_cleans_temp_when_staging_creation_fails {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $env:CODEX_HOME = Join-Path $script:_TestTmp.FullName 'codex-home'
    Write-TestCodexPins
    $script:CodexTempCreated = $null
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'tar') { return [pscustomobject]@{ Source = 'mock-tar' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'New-Item' {
        param($ItemType, [switch]$Force, $Path)
        if ($Path -is [array] -and $Path.Count -eq 2 -and [string]$Path[0] -like '*codex-install-*') {
            $script:CodexTempCreated = [string]$Path[0]
            Microsoft.PowerShell.Management\New-Item -ItemType Directory -Force -Path $script:CodexTempCreated | Out-Null
            throw 'staging creation failed'
        }
        Microsoft.PowerShell.Management\New-Item @PSBoundParameters
    }

    Assert-Throws { InstallCodex 6>&1 | Out-Null } 'staging creation failure should surface'
    Assert-False (Test-Path -LiteralPath $script:CodexTempCreated) 'partial Codex temp directory should be removed'
}

function test_installcodex_stages_verified_package_before_activation {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $env:CODEX_HOME = Join-Path $script:_TestTmp.FullName 'codex-home'
    $archiveHash = Get-TestSha256 'archive'
    Write-TestCodexPins -X64Hash $archiveHash
    $script:CodexCalls = @()
    $script:ActivatedCodexBin = $null
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'tar') { return [pscustomobject]@{ Source = 'mock-tar' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        $script:CodexCalls += "download:$Uri"
        [IO.File]::WriteAllText($OutFile, 'archive')
    }
    Set-CommandMock 'tar' {
        $script:CodexCalls += "extract:$($args -join ' ')"
        $global:LASTEXITCODE = 0
    }
    Set-FunctionMock 'Test-CodexRelease' {
        param($ReleaseDir, $ExpectedVersion)
        $script:CodexCalls += "verify:$ReleaseDir"
        $true
    }
    Set-FunctionMock 'Set-CodexActivePath' {
        param($BinDir, $ManagedRoot)
        $script:ActivatedCodexBin = $BinDir
        $script:CodexCalls += "activate:$BinDir"
    }

    InstallCodex 6>&1 | Out-Null

    $release = Join-Path $env:CODEX_HOME "packages\standalone\releases\1.2.3-x86_64-pc-windows-msvc-$($archiveHash.Substring(0, 12))"
    Assert-FileExists $release
    Assert-Equals (Join-Path $release 'bin') $script:ActivatedCodexBin
    Assert-Contains ($script:CodexCalls -join "`n") 'download:https://github.com/openai/codex/releases/download/rust-v1.2.3/codex-package-x86_64-pc-windows-msvc.tar.gz'
    $finalVerification = [Array]::IndexOf($script:CodexCalls, "verify:$release")
    $activation = [Array]::IndexOf($script:CodexCalls, "activate:$($script:ActivatedCodexBin)")
    Assert-True ($finalVerification -ge 0 -and $finalVerification -lt $activation) 'final release should be verified before PATH activation'
}

function test_installpilanguageservers_installs_pinned_npm_servers {
    $script:LspInstalled = $false
    $script:NpmCalls = @()
    Set-CommandMock 'vtsls' {
        if ($script:LspInstalled) { '0.3.0' } else { '0.0.0' }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'bash-language-server' {
        if ($script:LspInstalled) { '5.6.0' } else { '0.0.0' }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'npm' {
        $script:NpmCalls += ,($args -join ' ')
        $script:LspInstalled = $true
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'shellcheck' { $global:LASTEXITCODE = 0 }

    InstallPiLanguageServers

    $install = $script:NpmCalls -join "`n"
    Assert-Contains $install 'install --global'
    Assert-Contains $install '@vtsls/language-server@0.3.0'
    Assert-Contains $install 'bash-language-server@5.6.0'
}

function test_installpi_repairs_current_package {
    $script:PiRepaired = $false
    $pinnedVersion = Get-PinnedPiVersion
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return [pscustomobject]@{ Source = 'mock-pi' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'pi' {
        if (($args -join ' ') -eq '--version') { $pinnedVersion }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'RepairPiCompactionSteering' { $script:PiRepaired = $true }

    InstallPi -Update

    Assert-True $script:PiRepaired 'Pi install should repair auto-compaction steering delivery'
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

    $pinnedVersion = Get-PinnedPiVersion
    Assert-Equals "install --global @earendil-works/pi-coding-agent@$pinnedVersion" $script:NpmCalls[0]
}

function test_installpi_does_not_reconcile_extensions_before_locked_config {
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

    Assert-False ($script:PiCalls -contains 'update --extensions') 'Pi install should not reconcile extensions before locked config is active'
}

function test_installpi_skips_current_package_during_update {
    $script:NpmCalls = @()
    $script:PiCalls = @()
    $pinnedVersion = Get-PinnedPiVersion
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return [pscustomobject]@{ Source = 'mock-pi' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' {
        $script:NpmCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'pi' {
        $call = $args -join ' '
        $script:PiCalls += ,$call
        if ($call -eq '--version') { $pinnedVersion }
        $global:LASTEXITCODE = 0
    }

    InstallPi -Update

    Assert-Equals 0 $script:NpmCalls.Count 'current pinned Pi package should not query npm or reinstall'
    Assert-False ($script:PiCalls -contains 'update --extensions') 'Pi package update should leave extension reconciliation to InstallAi'
}

function test_installpi_replaces_unpinned_version_during_update {
    $script:NpmCalls = @()
    $pinnedVersion = Get-PinnedPiVersion
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'pi') { return [pscustomobject]@{ Source = 'mock-pi' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'npm' {
        $script:NpmCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'pi' {
        if (($args -join ' ') -eq '--version') { '0.0.0' }
        $global:LASTEXITCODE = 0
    }

    InstallPi -Update

    Assert-True ($script:NpmCalls -contains "install --global @earendil-works/pi-coding-agent@$pinnedVersion") 'update should install reviewed Pi pin'
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

    $extensions = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package.json') | ConvertFrom-Json
    Assert-True ($extensions.dependencies.'pi-subagents' -match '^\d+\.\d+\.\d+$') 'pi-subagents should use an exact version'
    Assert-Equals 'gpt-5.6-sol' $settings.defaultModel
    Assert-Equals 'medium' $settings.defaultThinkingLevel
    Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.defaultModel
    Assert-Equals 'medium' $settings.subagents.defaultThinking
    Assert-True $settings.subagents.modelScope.enforce
    Assert-Equals 1 @($settings.subagents.modelScope.allow).Count
    Assert-Equals 'openai-codex/*' @($settings.subagents.modelScope.allow)[0]

    Assert-False ($settings.subagents.agentOverrides.PSObject.Properties.Name -contains 'advisor') 'advisor aliases oracle and should not have a dead override'
    Assert-Equals 'openai-codex/gpt-5.6-sol' $settings.subagents.agentOverrides.oracle.model
    Assert-Equals 'xhigh' $settings.subagents.agentOverrides.oracle.thinking
    foreach ($agent in 'delegate', 'scout', 'worker') {
        $override = $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value
        Assert-Equals 'openai-codex/gpt-5.6-luna' $override.model
        Assert-Equals 'medium' $override.thinking
    }
    Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.agentOverrides.researcher.model
    Assert-Equals 'high' $settings.subagents.agentOverrides.researcher.thinking
    Assert-Equals 'openai-codex/gpt-5.6-sol' $settings.subagents.agentOverrides.reviewer.model
    Assert-Equals 'xhigh' $settings.subagents.agentOverrides.reviewer.thinking
}

function test_pi_lsp_package_is_pinned {
    $path = Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package.json'
    $extensions = Get-Content -Raw $path | ConvertFrom-Json

    Assert-Equals '0.49.4' $extensions.dependencies.'@narumitw/pi-lsp'
}

function test_windows_pi_lsp_config_uses_only_supported_servers {
    $path = Join-Path $script:RepoDir 'config\windows\ai\pi\pi-lsp.json'
    $config = Get-Content -Raw $path | ConvertFrom-Json

    Assert-Equals 'vtsls' @($config.servers.vtsls.command)[0]
    Assert-Equals 'bash-language-server' @($config.servers.'bash-language-server'.command)[0]
    Assert-False ($config.servers.PSObject.Properties.Name -contains 'nil') 'Windows LSP config should not advertise unavailable nil'
}

function test_syncpiconfigs_creates_writable_seed_files {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $windowsSeedDir = Join-Path $script:DotfilesDir 'config\windows\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir, $windowsSeedDir | Out-Null
    '{"theme":"dark"}' | Set-Content (Join-Path $seedDir 'settings.json')
    '{"mcpServers":{"unixOnly":{"command":"unix"}}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    '{"globalConcurrencyLimit":7}' | Set-Content (Join-Path $seedDir 'subagent-config.json')
    '{"mcpServers":{"windowsOnly":{"command":"windows"}}}' | Set-Content (Join-Path $windowsSeedDir 'mcp.json')
    '{"servers":{"vtsls":{"command":["vtsls","--stdio"]}}}' | Set-Content (Join-Path $windowsSeedDir 'pi-lsp.json')
    'extension' | Set-Content (Join-Path $seedDir 'caveman-default.js')
    'extension' | Set-Content (Join-Path $seedDir 'ponytail-default.js')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    'extension' | Set-Content (Join-Path $seedDir 'windows-exit.js')

    SyncPiConfigs

    $settings = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $mcp = Join-Path $env:USERPROFILE '.pi\agent\mcp.json'
    $subagent = Join-Path $env:USERPROFILE '.pi\agent\extensions\subagent\config.json'
    $lsp = Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    $baseDir = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    Assert-FileExists $settings
    Assert-FileExists $mcp
    Assert-FileExists $subagent
    Assert-FileExists $lsp
    Assert-FileExists (Join-Path $baseDir 'settings.json')
    Assert-FileExists (Join-Path $baseDir 'mcp.json')
    Assert-FileExists (Join-Path $baseDir 'subagent-config.json')
    Assert-Contains (Get-Content -Raw $mcp) '"windowsOnly"'
    Assert-False ((Get-Content -Raw $mcp) -like '*unixOnly*') 'Windows should deploy Windows MCP seed'
    Assert-Contains (Get-Content -Raw $lsp) '"vtsls"'
    Assert-FileExists (Join-Path $extensionDir 'caveman-default.js')
    Assert-FileExists (Join-Path $extensionDir 'ponytail-default.js')
    Assert-FileExists (Join-Path $extensionDir 'codex-status.js')
    Assert-FileExists (Join-Path $extensionDir 'windows-exit.js')
    Assert-False ([bool](Get-Item $settings).LinkType) 'Pi settings should stay writable'
}

function test_syncpiconfigs_replaces_stale_live_subagents {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $windowsSeedDir = Join-Path $script:DotfilesDir 'config\windows\ai\pi'
    $mergeDir = Join-Path $script:DotfilesDir 'scripts\seed_merge'
    $targetDir = Join-Path $env:USERPROFILE '.pi\agent'
    $subagentDir = Join-Path $targetDir 'extensions\subagent'
    New-Item -ItemType Directory -Force -Path $seedDir, $windowsSeedDir, $mergeDir, $targetDir, $subagentDir | Out-Null
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
    '{"globalConcurrencyLimit":7}' | Set-Content (Join-Path $seedDir 'subagent-config.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $windowsSeedDir 'mcp.json')
    '{"servers":{"vtsls":{"command":["vtsls","--stdio"]}}}' | Set-Content (Join-Path $windowsSeedDir 'pi-lsp.json')
    '{"servers":{"nil":{"command":["nil"]}}}' | Set-Content (Join-Path $targetDir 'pi-lsp.json')
    '{"globalConcurrencyLimit":99}' | Set-Content (Join-Path $subagentDir 'config.json')
    'extension' | Set-Content (Join-Path $seedDir 'caveman-default.js')
    'extension' | Set-Content (Join-Path $seedDir 'ponytail-default.js')
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
        $lsp = Get-Content -Raw (Join-Path $targetDir 'pi-lsp.json') | ConvertFrom-Json
        Assert-True ($lsp.servers.PSObject.Properties.Name -contains 'vtsls') 'Windows LSP config should be copied'
        Assert-False ($lsp.servers.PSObject.Properties.Name -contains 'nil') 'Authoritative Windows LSP config should remove stale servers'
        $subagent = Get-Content -Raw (Join-Path $subagentDir 'config.json') | ConvertFrom-Json
        Assert-Equals 7 $subagent.globalConcurrencyLimit
    } finally {
        (Get-Item $seed).IsReadOnly = $false
    }
}
