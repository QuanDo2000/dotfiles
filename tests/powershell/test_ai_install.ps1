# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
    $script:OriginalTestPiSourceHash = (Get-Command Test-PiSourceHash).ScriptBlock
    $releaseCheck = Get-Command Test-CodexRelease -ErrorAction SilentlyContinue
    $pathSetter = Get-Command Set-CodexActivePath -ErrorAction SilentlyContinue
    $codebaseReleaseCheck = Get-Command Test-CodebaseMemoryRelease -ErrorAction SilentlyContinue
    $codebasePathSetter = Get-Command Set-CodebaseMemoryActivePath -ErrorAction SilentlyContinue
    $codebaseInvoker = Get-Command Invoke-CodebaseMemoryCommand -ErrorAction SilentlyContinue
    $codebaseArchiveCheck = Get-Command Test-CodebaseMemoryArchive -ErrorAction SilentlyContinue
    $codebaseProcessStopper = Get-Command Stop-CodebaseMemoryProcesses -ErrorAction SilentlyContinue
    $codebaseConfigAccessTester = Get-Command Test-CodebaseMemoryConfigDatabaseAccess -ErrorAction SilentlyContinue
    $codebaseConfigRepairer = Get-Command Repair-CodebaseMemoryConfigDatabase -ErrorAction SilentlyContinue
    $codebaseActivePathTester = Get-Command Test-CodebaseMemoryActivePath -ErrorAction SilentlyContinue
    $windowsTarExpander = Get-Command Expand-WindowsTarArchive -ErrorAction SilentlyContinue
    $script:OriginalTestCodexRelease = if ($releaseCheck) { $releaseCheck.ScriptBlock } else { $null }
    $script:OriginalSetCodexActivePath = if ($pathSetter) { $pathSetter.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryRelease = if ($codebaseReleaseCheck) { $codebaseReleaseCheck.ScriptBlock } else { $null }
    $script:OriginalSetCodebaseMemoryActivePath = if ($codebasePathSetter) { $codebasePathSetter.ScriptBlock } else { $null }
    $script:OriginalInvokeCodebaseMemoryCommand = if ($codebaseInvoker) { $codebaseInvoker.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryArchive = if ($codebaseArchiveCheck) { $codebaseArchiveCheck.ScriptBlock } else { $null }
    $script:OriginalStopCodebaseMemoryProcesses = if ($codebaseProcessStopper) { $codebaseProcessStopper.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryConfigDatabaseAccess = if ($codebaseConfigAccessTester) { $codebaseConfigAccessTester.ScriptBlock } else { $null }
    $script:OriginalRepairCodebaseMemoryConfigDatabase = if ($codebaseConfigRepairer) { $codebaseConfigRepairer.ScriptBlock } else { $null }
    $script:OriginalTestCodebaseMemoryActivePath = if ($codebaseActivePathTester) { $codebaseActivePathTester.ScriptBlock } else { $null }
    $script:OriginalExpandWindowsTarArchive = if ($windowsTarExpander) { $windowsTarExpander.ScriptBlock } else { $null }
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
    Set-FunctionMock 'Test-PiSourceHash' $script:OriginalTestPiSourceHash
    if ($script:OriginalTestCodexRelease) { Set-FunctionMock 'Test-CodexRelease' $script:OriginalTestCodexRelease }
    if ($script:OriginalSetCodexActivePath) { Set-FunctionMock 'Set-CodexActivePath' $script:OriginalSetCodexActivePath }
    if ($script:OriginalTestCodebaseMemoryRelease) { Set-FunctionMock 'Test-CodebaseMemoryRelease' $script:OriginalTestCodebaseMemoryRelease }
    if ($script:OriginalSetCodebaseMemoryActivePath) { Set-FunctionMock 'Set-CodebaseMemoryActivePath' $script:OriginalSetCodebaseMemoryActivePath }
    if ($script:OriginalInvokeCodebaseMemoryCommand) { Set-FunctionMock 'Invoke-CodebaseMemoryCommand' $script:OriginalInvokeCodebaseMemoryCommand }
    if ($script:OriginalTestCodebaseMemoryArchive) { Set-FunctionMock 'Test-CodebaseMemoryArchive' $script:OriginalTestCodebaseMemoryArchive }
    if ($script:OriginalStopCodebaseMemoryProcesses) { Set-FunctionMock 'Stop-CodebaseMemoryProcesses' $script:OriginalStopCodebaseMemoryProcesses }
    if ($script:OriginalTestCodebaseMemoryConfigDatabaseAccess) { Set-FunctionMock 'Test-CodebaseMemoryConfigDatabaseAccess' $script:OriginalTestCodebaseMemoryConfigDatabaseAccess }
    if ($script:OriginalRepairCodebaseMemoryConfigDatabase) { Set-FunctionMock 'Repair-CodebaseMemoryConfigDatabase' $script:OriginalRepairCodebaseMemoryConfigDatabase }
    if ($script:OriginalTestCodebaseMemoryActivePath) {
        Set-FunctionMock 'Test-CodebaseMemoryActivePath' $script:OriginalTestCodebaseMemoryActivePath
    } else {
        Remove-Item function:\Test-CodebaseMemoryActivePath -ErrorAction SilentlyContinue
    }
    if ($script:OriginalExpandWindowsTarArchive) { Set-FunctionMock 'Expand-WindowsTarArchive' $script:OriginalExpandWindowsTarArchive }
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
    $codexSeed = Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\ai\codex\config.toml')
    $piSeed = Get-Content -Raw (Join-Path $script:RepoDir 'config\windows\ai\pi\mcp.json') | ConvertFrom-Json

    Assert-False ($text -like '*codebase-memory-mcp/$releaseTag/install.ps1*') 'remote codebase-memory installer should not execute'
    Assert-False ($text -like '*--clients=codex*') 'repo-owned agent configs should not be regenerated'
    Assert-False (Test-Path (Join-Path $script:RepoDir 'scripts\seed_merge\toml_tools.py')) 'generated-config repair tool should be removed'
    Assert-False ($text -like '*releases/latest*codebase-memory*') 'Windows codebase-memory release should not float'
    Assert-True ($pins.version -match '^\d+\.\d+\.\d+$') 'version should be exact semver'
    Assert-True ($pins.windows.amd64.sha256 -match '^[0-9a-f]{64}$') 'amd64 hash should be pinned'
    Assert-True ($pins.windows.arm64.sha256 -match '^[0-9a-f]{64}$') 'arm64 hash should be pinned'
    Assert-True ($pins.windows.amd64.file -match '^codebase-memory-mcp(?:-ui)?-windows-amd64.*\.zip$') 'amd64 file should be pinned'
    Assert-Contains $nixPackage 'codebase-memory-mcp-release.json'
    Assert-Contains $nixPackage '${source.file}'
    Assert-Contains $codexSeed '[mcp_servers.codebase-memory-mcp]'
    Assert-Equals 'codebase-memory-mcp' $piSeed.mcpServers.codebaseMemory.command
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

function test_remove_retired_fff_mcp_cleans_only_executables {
    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $exe = Join-Path $binDir 'fff-mcp.exe'
    $launcher = Join-Path $binDir 'fff-mcp-agent.cmd'
    $frecency = Join-Path $env:LOCALAPPDATA 'fff\frecency'
    New-Item -ItemType Directory -Force -Path (Split-Path $frecency -Parent) | Out-Null
    'retired' | Set-Content -NoNewline $exe
    'retired' | Set-Content -NoNewline $launcher
    'state' | Set-Content -NoNewline $frecency
    $script:FffProcessesStopped = @()
    Set-CommandMock 'Get-Process' {
        @(
            [pscustomobject]@{ ProcessName = 'fff-mcp'; Path = $exe },
            [pscustomobject]@{ ProcessName = 'fff-mcp'; Path = 'C:\other\fff-mcp.exe' }
        )
    }
    Set-CommandMock 'Stop-Process' { $script:FffProcessesStopped = @($input) }
    Set-CommandMock 'Wait-Process' { }

    Remove-RetiredFffMcp

    Assert-Equals 1 $script:FffProcessesStopped.Count
    Assert-Equals $exe $script:FffProcessesStopped[0].Path
    Assert-False (Test-Path -LiteralPath $exe) 'retired FFF executable should be removed'
    Assert-False (Test-Path -LiteralPath $launcher) 'retired FFF launcher should be removed'
    Assert-FileExists $frecency 'FFF frecency state must be preserved'
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
    if (-not $windowsPowerShell) { Skip-Test 'Windows PowerShell unavailable'; return }

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
    Assert-True ($pins.version -match '^\d+\.\d+\.\d+$') 'version should be exact semver'
    Assert-True ($pins.windows.x86_64 -match '^[0-9a-f]{64}$') 'x86_64 hash should be pinned'
    Assert-True ($pins.windows.aarch64 -match '^[0-9a-f]{64}$') 'aarch64 hash should be pinned'
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
    $env:CODEX_HOME = Join-Path $env:USERPROFILE 'custom-codex-home'
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:CODEX_HOME 'config.toml'
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




function Initialize-TestAiInstructions($Content = 'shared instructions') {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $source = Join-Path $script:DotfilesDir 'config\shared\ai\AGENTS.md'
    New-Item -ItemType Directory -Force -Path (Split-Path $source -Parent) | Out-Null
    $Content | Set-Content $source
    return $source
}

function Get-TestAiInstructionTargets {
    return @(
        (Join-Path $env:USERPROFILE '.codex\AGENTS.md'),
        (Join-Path $env:USERPROFILE '.pi\agent\AGENTS.md')
    )
}

function test_syncaiinstructions_skips_unchanged_regular_files_for_codex_and_pi {
    $source = Initialize-TestAiInstructions
    foreach ($target in Get-TestAiInstructionTargets) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    $script:AiInstructionCopies = 0
    Set-CommandMock 'Copy-Item' { $script:AiInstructionCopies++ }

    SyncAiInstructions

    Assert-Equals 0 $script:AiInstructionCopies
}

function test_syncaiinstructions_replaces_changed_files_for_codex_and_pi {
    Initialize-TestAiInstructions | Out-Null
    foreach ($target in Get-TestAiInstructionTargets) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        'old instructions' | Set-Content $target
    }

    SyncAiInstructions

    foreach ($target in Get-TestAiInstructionTargets) {
        Assert-Equals 'shared instructions' ((Get-Content -Raw $target).Trim())
    }
}

function test_syncaiinstructions_creates_missing_files_for_codex_and_pi {
    Initialize-TestAiInstructions | Out-Null

    SyncAiInstructions

    foreach ($target in Get-TestAiInstructionTargets) {
        Assert-FileExists $target
        Assert-Equals 'shared instructions' ((Get-Content -Raw $target).Trim())
    }
}

function test_syncaiinstructions_does_not_skip_linked_destinations_for_codex_and_pi {
    Initialize-TestAiInstructions | Out-Null
    $external = Join-Path $script:_TestTmp.FullName 'linked-AGENTS.md'
    'shared instructions' | Set-Content $external
    foreach ($target in Get-TestAiInstructionTargets) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        New-Item -ItemType SymbolicLink -Path $target -Target $external | Out-Null
    }
    SyncAiInstructions

    foreach ($target in Get-TestAiInstructionTargets) {
        Assert-False ([bool](Get-Item -LiteralPath $target -Force).LinkType) 'linked destination should become a regular file'
        Assert-Equals 'shared instructions' ((Get-Content -Raw $target).Trim())
    }
    Assert-Equals 'shared instructions' ((Get-Content -Raw $external).Trim())
}

function Assert-AiInstructionCopyFailurePreservesTarget($Target) {
    Initialize-TestAiInstructions | Out-Null
    $external = Join-Path $script:_TestTmp.FullName "linked-AGENTS-$([Guid]::NewGuid().ToString('N')).md"
    'old instructions' | Set-Content $external
    New-Item -ItemType Directory -Force -Path (Split-Path $Target -Parent) | Out-Null
    New-Item -ItemType SymbolicLink -Path $Target -Target $external | Out-Null
    $script:AiInstructionStaged = $false
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        if ($Destination -like "$Target.tmp.*") {
            $script:AiInstructionStaged = $true
            'partial instructions' | Set-Content $Destination
            throw 'simulated copy failure'
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }

    Assert-Throws { SyncAiInstructions } 'staging copy failure should be reported'

    Assert-True $script:AiInstructionStaged 'copy should stage beside destination'
    Assert-True ([bool](Get-Item -LiteralPath $Target -Force).LinkType) 'linked destination should be preserved'
    Assert-Equals 'old instructions' ((Get-Content -Raw $Target).Trim())
    Assert-Equals 'old instructions' ((Get-Content -Raw $external).Trim())
    Assert-Equals 0 @((Get-ChildItem -LiteralPath (Split-Path $Target -Parent) -Filter 'AGENTS.md.tmp.*' -Force)).Count
}

function test_syncaiinstructions_cleans_temp_and_preserves_codex_link_when_copy_fails {
    Assert-AiInstructionCopyFailurePreservesTarget (Join-Path $env:USERPROFILE '.codex\AGENTS.md')
}

function test_syncaiinstructions_cleans_temp_and_preserves_pi_link_when_copy_fails {
    Assert-AiInstructionCopyFailurePreservesTarget (Join-Path $env:USERPROFILE '.pi\agent\AGENTS.md')
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

function test_install_skill_directory_skips_current_copy {
    $source = Join-Path $script:_TestTmp.FullName 'source-skill'
    $target = Join-Path $script:_TestTmp.FullName 'target-skill'
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'references'), (Join-Path $target 'references') | Out-Null
    'same' | Set-Content (Join-Path $source 'SKILL.md')
    'same' | Set-Content (Join-Path $target 'SKILL.md')
    'same reference' | Set-Content (Join-Path $source 'references\details.md')
    'same reference' | Set-Content (Join-Path $target 'references\details.md')
    $script:SkillCopies = 0
    Set-CommandMock 'Copy-Item' { $script:SkillCopies++ }

    try {
        Install-SkillDirectory $source $target
    } finally {
        Clear-CommandMock 'Copy-Item'
    }

    Assert-Equals 0 $script:SkillCopies
    Assert-Contains (Get-Content -Raw (Join-Path $target 'SKILL.md')) 'same'
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
    $skills = @('systematic-debugging', 'test-driven-development')
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
    foreach ($skill in 'caveman', 'ponytail', 'ponytail-help', 'diff-review-qa', 'verification-before-completion', 'efficient-subagent-use', 'ponytail-audit', 'ponytail-debt', 'ponytail-gain', 'ponytail-review') {
        New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot $skill) | Out-Null
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
    foreach ($skill in 'caveman', 'ponytail', 'ponytail-help', 'diff-review-qa', 'verification-before-completion', 'efficient-subagent-use', 'ponytail-audit', 'ponytail-debt', 'ponytail-gain', 'ponytail-review') {
        Assert-False (Test-Path (Join-Path $targetRoot $skill)) "Retired skill remains for $skill"
        Assert-False (Test-Path (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill")) "Retired Pi skill remains for $skill"
    }
}

function test_repaircodebasememoryconfigdatabase_elevates_acl_repair {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Skip-Test 'Windows-only ACL repair'; return }

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

function test_installcodebasememory_skips_current_managed_configuration {
    $script:Dry = $false
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    Write-TestCodebaseMemoryPins
    $release = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\releases\1.2.3-windows-amd64-cccccccccccc'
    $legacyRoot = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp'
    $env:CODEX_HOME = Join-Path $env:USERPROFILE 'custom-codex-home'
    $codexConfig = Join-Path $env:CODEX_HOME 'config.toml'
    $statePath = Join-Path $legacyRoot 'managed-state.json'
    New-Item -ItemType Directory -Force -Path $release, (Split-Path $codexConfig -Parent) | Out-Null
    '[mcp_servers.codebase-memory-mcp]' | Set-Content -LiteralPath $codexConfig
    @{
        version = '1.2.3'
        releaseDir = $release
        codexConfigSha256 = (Get-FileHash -LiteralPath $codexConfig -Algorithm SHA256).Hash
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8
    $script:CodebaseMemoryCalls = @()
    Set-FunctionMock 'Test-CodebaseMemoryRelease' { $true }
    Set-FunctionMock 'Test-CodebaseMemoryActivePath' { $true }
    Set-FunctionMock 'Test-CodebaseMemoryConfigDatabaseAccess' { $true }
    Set-FunctionMock 'Stop-CodebaseMemoryProcesses' { $script:CodebaseMemoryCalls += 'stop' }
    Set-FunctionMock 'Repair-CodebaseMemoryConfigDatabase' { $script:CodebaseMemoryCalls += 'repair' }
    Set-FunctionMock 'Set-CodebaseMemoryActivePath' { $script:CodebaseMemoryCalls += 'activate' }
    Set-FunctionMock 'Invoke-CodebaseMemoryCommand' {
        param($Executable, $FailureMessage, $Arguments)
        $call = $Arguments -join ' '
        $script:CodebaseMemoryCalls += $call
        if ($call -like 'config get *') { return 'true' }
    }

    InstallCodebaseMemory -Update 6>&1 | Out-Null

    Assert-Equals "config get auto_index`nconfig get auto_watch" ($script:CodebaseMemoryCalls -join "`n")
    Assert-False (($script:CodebaseMemoryCalls -join "`n").Contains('install -y --clients=codex')) 'current managed configuration should not invoke the client generator'
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
    Assert-DirectoryExists $release
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
    $codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $codexConfig -Parent) | Out-Null
    '[mcp_servers.codebase-memory-mcp]' | Set-Content -LiteralPath $codexConfig
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
    Assert-DirectoryExists $release
    Assert-Equals $release $script:ActivatedCodebaseMemoryDir
    $calls = $script:CodebaseMemoryCalls -join "`n"
    Assert-Contains $calls 'download:https://github.com/DeusData/codebase-memory-mcp/releases/download/v1.2.3/codebase-memory-mcp-windows-amd64.zip'
    Assert-False $calls.Contains("run:${executable}:install -y --clients=codex") 'repo-owned agent configs should not invoke the client generator'
    Assert-Contains $calls 'stop:processes'
    Assert-Contains $calls 'repair:config-database'
    Assert-Contains $calls "run:${executable}:config set auto_index true"
    Assert-Contains $calls "run:${executable}:config set auto_watch true"
    $state = Get-Content -Raw (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\managed-state.json') | ConvertFrom-Json
    Assert-Equals '1.2.3' $state.version
    Assert-Equals $release $state.releaseDir
    Assert-Equals (Get-FileHash (Join-Path $env:USERPROFILE '.codex\config.toml') -Algorithm SHA256).Hash $state.codexConfigSha256
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
    if (-not $windowsPowerShell -or -not $env:SystemRoot) { Skip-Test 'Windows PowerShell unavailable'; return }
    $tarCommand = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tarCommand -PathType Leaf)) { Skip-Test 'Windows tar unavailable'; return }

    $source = Join-Path $script:_TestTmp.FullName 'codex-package-source'
    $archive = Join-Path $script:_TestTmp.FullName 'codex-package.tar.gz'
    $destination = Join-Path $script:_TestTmp.FullName 'codex-package-extracted'
    foreach ($relativePath in 'codex-package.json', 'bin\codex.exe', 'bin\codex-code-mode-host.exe', 'codex-path\rg.exe', 'codex-resources\codex-command-runner.exe', 'codex-resources\codex-windows-sandbox-setup.exe') {
        $path = Join-Path $source $relativePath
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        [IO.File]::WriteAllText($path, $relativePath)
    }
    & $tarCommand -czf $archive -C $source .
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
    & (Join-Path $env:SystemRoot 'System32\tar.exe') -xzf $env:CODEX_TEST_ARCHIVE -C $env:CODEX_TEST_DESTINATION
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
    Set-FunctionMock 'Expand-WindowsTarArchive' {
        param($Archive, $Destination)
        $script:CodexCalls += "extract:$Archive -C $Destination"
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
    Assert-DirectoryExists $release
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

function test_installpilanguageservers_update_skips_current_pinned_servers {
    $script:NpmCalls = @()
    Set-CommandMock 'vtsls' { '0.3.0'; $global:LASTEXITCODE = 0 }
    Set-CommandMock 'bash-language-server' { '5.6.0'; $global:LASTEXITCODE = 0 }
    Set-CommandMock 'shellcheck' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'npm' { $script:NpmCalls += ,($args -join ' '); $global:LASTEXITCODE = 0 }

    InstallPiLanguageServers -Update

    Assert-Equals 0 $script:NpmCalls.Count 'update should not reinstall current pinned language servers'
}

function Write-TestPatchedPiSession($Path) {
    "this._autoCompactionAbortController = undefined;`nawait this.waitForIdle();" | Set-Content -LiteralPath $Path
}

function test_installpi_installs_verified_versioned_release {
    $version = Get-PinnedPiVersion
    $script:NpmArgs = ''
    Set-CommandMock 'Invoke-WebRequest' { param($Uri, $OutFile) [IO.File]::WriteAllText($OutFile, 'archive') }
    Set-FunctionMock 'Test-PiSourceHash' { $true }
    Set-FunctionMock 'Expand-WindowsTarArchive' {
        param($Archive, $Destination)
        $package = Join-Path $Destination 'package'
        New-Item -ItemType Directory -Force -Path (Join-Path $package 'dist\core') | Out-Null
        Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $package 'npm-shrinkwrap.json')
        "{`"version`":`"$version`",`"devDependencies`":{`"typescript`":`"1.0.0`"}}" | Set-Content (Join-Path $package 'package.json')
        'entry' | Set-Content (Join-Path $package 'dist\cli.js')
        Write-TestPatchedPiSession (Join-Path $package 'dist\core\agent-session.js')
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'npm' {
        $script:NpmArgs = $args -join ' '
        $prefix = $args[[Array]::IndexOf($args, '--prefix') + 1]
        $script:NpmSawDevDependencies = [bool]((Get-Content -Raw (Join-Path $prefix 'package.json') | ConvertFrom-Json).devDependencies)
        $global:LASTEXITCODE = 0
    }

    InstallPi

    Assert-Contains $script:NpmArgs 'ci --prefix'
    Assert-Contains $script:NpmArgs '--omit=dev --ignore-scripts'
    Assert-False $script:NpmSawDevDependencies 'npm ci manifest must match production-only reviewed shrinkwrap'
    $launcher = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\bin\pi.cmd'
    Assert-FileExists $launcher
    Assert-Equals (Split-Path $launcher -Parent) (($env:Path -split ';')[0])
}

function test_installpi_verifies_cached_release_and_rejects_tamper {
    $version = Get-PinnedPiVersion
    $root = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    $releaseId = -join ((Get-PiSourceDigest (Get-PinnedPiSourceHash)) | ForEach-Object { $_.ToString('x2') })
    $release = Join-Path $root "releases\$version-$($releaseId.Substring(0, 12))"
    New-Item -ItemType Directory -Force -Path (Join-Path $release 'dist\core') | Out-Null
    Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $release 'npm-shrinkwrap.json')
    '{"version":"0.84.2"}' | Set-Content (Join-Path $release 'package.json')
    'entry' | Set-Content (Join-Path $release 'dist\cli.js')
    Write-TestPatchedPiSession (Join-Path $release 'dist\core\agent-session.js')
    (Get-PiReleaseDigest $release) | Set-Content (Join-Path $release '.release.sha256') -NoNewline
    InstallPi
    'tampered' | Set-Content (Join-Path $release 'dist\cli.js')
    Assert-Throws { InstallPi } 'cached content tamper must be rejected'
}

function test_getpinnedpiversion_rejects_invalid_json {
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'invalid-pi-lock'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:DotfilesDir 'packages') | Out-Null
    '{"name":"@earendil-works/pi-coding-agent","version":"0.84.2"' | Set-Content (Join-Path $script:DotfilesDir 'packages\pi-agent-npm-shrinkwrap.json')

    Assert-Throws { Get-PinnedPiVersion } 'invalid JSON lock must fail closed'
}

function test_dotfile_script_is_ascii_for_windows_powershell {
    $nonAscii = @([IO.File]::ReadAllBytes($script:DotfileScript) | Where-Object { $_ -gt 127 })
    Assert-Equals 0 $nonAscii.Count 'Windows PowerShell 5.1 reads UTF-8 without BOM as ANSI'
}

function test_getpinnedpiversion_runs_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { Skip-Test 'Windows PowerShell unavailable'; return }
    $escapedScript = $script:DotfileScript.Replace("'", "''")
    $probe = ". '$escapedScript' -NoMain; if ((Get-PinnedPiVersion) -notmatch '^\d+\.\d+\.\d+') { exit 1 }"

    $oldDotfilesDir = $env:DOTFILES_DIR
    try {
        $env:DOTFILES_DIR = $script:RepoDir
        & $windowsPowerShell.Source -NoProfile -NonInteractive -Command $probe
        Assert-Equals 0 $LASTEXITCODE
    } finally {
        if ($null -eq $oldDotfilesDir) { Remove-Item Env:DOTFILES_DIR -ErrorAction SilentlyContinue } else { $env:DOTFILES_DIR = $oldDotfilesDir }
    }
}

function test_installpi_source_checksum_fails_before_install {
    Set-CommandMock 'Invoke-WebRequest' { param($Uri, $OutFile) [IO.File]::WriteAllText($OutFile, 'bad') }
    Set-FunctionMock 'Test-PiSourceHash' { $false }
    Set-CommandMock 'npm' { throw 'npm must not run after checksum mismatch' }
    Assert-Throws { InstallPi } 'checksum mismatch must fail before npm'
}

function test_pi_release_validation_requires_version_and_entry {
    $dir = Join-Path $script:_TestTmp.FullName 'pi-release'
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'dist\core') | Out-Null
    $lock = Get-Content -Raw (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json')
    Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $dir 'npm-shrinkwrap.json')
    '{"version":"0.84.2","dependencies":{"example-package":"1.0.0"}}' | Set-Content (Join-Path $dir 'package.json')
    'entry' | Set-Content (Join-Path $dir 'dist\cli.js')
    Write-TestPatchedPiSession (Join-Path $dir 'dist\core\agent-session.js')
    (Get-PiReleaseDigest $dir) | Set-Content (Join-Path $dir '.release.sha256') -NoNewline
    Assert-False (Test-PiRelease $dir '0.84.2' $lock) 'release missing dependency closure must fail'
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'node_modules\example-package') | Out-Null
    '{}' | Set-Content (Join-Path $dir 'node_modules\example-package\package.json')
    (Get-PiReleaseDigest $dir) | Set-Content (Join-Path $dir '.release.sha256') -NoNewline
    Assert-True (Test-PiRelease $dir '0.84.2' $lock)
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

    Assert-Equals 'openai-codex/gpt-5.6-sol' $settings.subagents.agentOverrides.oracle.model
    Assert-Equals 'xhigh' $settings.subagents.agentOverrides.oracle.thinking
    foreach ($agent in 'advisor', 'context-builder', 'delegate', 'planner') {
        Assert-True $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value.disabled "$agent should be disabled"
    }
    foreach ($agent in 'scout', 'worker') {
        $override = $settings.subagents.agentOverrides.PSObject.Properties[$agent].Value
        Assert-Equals 'openai-codex/gpt-5.6-luna' $override.model
        Assert-Equals 'medium' $override.thinking
    }
    Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.agentOverrides.researcher.model
    Assert-Equals 'high' $settings.subagents.agentOverrides.researcher.thinking
    Assert-Equals 'openai-codex/gpt-5.6-terra' $settings.subagents.agentOverrides.reviewer.model
    Assert-Equals 'high' $settings.subagents.agentOverrides.reviewer.thinking
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

function Initialize-TestPiConfigSeeds {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $windowsSeedDir = Join-Path $script:DotfilesDir 'config\windows\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir, $windowsSeedDir | Out-Null
    foreach ($name in 'settings.json', 'keybindings.json', 'web-search.json') {
        '{}' | Set-Content -LiteralPath (Join-Path $seedDir $name)
    }
    '{"globalConcurrencyLimit":7}' | Set-Content -LiteralPath (Join-Path $seedDir 'subagent-config.json')
    '{}' | Set-Content -LiteralPath (Join-Path $windowsSeedDir 'mcp.json')
    '{}' | Set-Content -LiteralPath (Join-Path $windowsSeedDir 'pi-lsp.json')
    'extension' | Set-Content -LiteralPath (Join-Path $seedDir 'codex-status.js')

    return [pscustomobject]@{
        Source = Join-Path $seedDir 'subagent-config.json'
        Target = Join-Path $env:USERPROFILE '.pi\agent\extensions\subagent\config.json'
        Base = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\subagent-config.json'
    }
}

function test_syncpiconfigs_replaces_linked_seed_baseline_without_touching_external_file {
    Initialize-TestPiConfigSeeds | Out-Null
    $base = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\settings.json'
    $external = Join-Path $script:_TestTmp.FullName 'external-settings.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $base -Parent) | Out-Null
    '{"external":true}' | Set-Content -LiteralPath $external
    New-Item -ItemType SymbolicLink -Path $base -Target $external | Out-Null

    SyncPiConfigs

    Assert-False ([bool](Get-Item -LiteralPath $base -Force).LinkType) 'linked baseline should become regular file'
    Assert-Equals '{}' ((Get-Content -Raw -LiteralPath $base).Trim())
    Assert-Equals '{"external":true}' ((Get-Content -Raw -LiteralPath $external).Trim())
}

function test_syncpiconfigs_restores_direct_copy_when_staged_replacement_fails {
    Initialize-TestPiConfigSeeds | Out-Null
    $destination = Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json'
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    'old lsp' | Set-Content -LiteralPath $destination
    $script:DirectCopyDestination = $destination
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($script:DirectCopyDestination).tmp.*" -and $Destination -eq $script:DirectCopyDestination) {
            throw 'simulated direct replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated direct replacement failure'
    Assert-Equals 'old lsp' ((Get-Content -Raw -LiteralPath $destination).Trim())
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $destination -Parent) -Filter 'pi-lsp.json.tmp.*' -Force).Count
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $destination -Parent) -Filter 'pi-lsp.json.backup.*' -Force).Count
}

function test_syncpiconfigs_rejects_directory_seed_baseline_without_partial_copy {
    Initialize-TestPiConfigSeeds | Out-Null
    $target = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $base = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\settings.json'
    New-Item -ItemType Directory -Force -Path $base | Out-Null

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'Pi config destination is a directory'
    Assert-Contains $failure $base
    Assert-False (Test-Path -LiteralPath $target) 'directory baseline should fail before target copy'
    Assert-False (Test-Path -LiteralPath (Join-Path $base 'settings.json')) 'source should not be copied inside baseline directory'
}

function test_syncpiconfigs_rejects_directory_direct_copy_destination {
    Initialize-TestPiConfigSeeds | Out-Null
    $destination = Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'Pi config destination is a directory'
    Assert-Contains $failure $destination
    Assert-True (Test-Path -LiteralPath $destination -PathType Container) 'directory collision should remain'
    Assert-False (Test-Path -LiteralPath (Join-Path $destination 'pi-lsp.json')) 'source should not be copied inside destination directory'
}

function test_syncpiconfigs_creates_writable_seed_files {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $windowsSeedDir = Join-Path $script:DotfilesDir 'config\windows\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir, $windowsSeedDir | Out-Null
    '{"theme":"dark"}' | Set-Content (Join-Path $seedDir 'settings.json')
    '{"app.model.cycleForward":[],"app.model.cycleBackward":[]}' | Set-Content (Join-Path $seedDir 'keybindings.json')
    '{"workflow":"none"}' | Set-Content (Join-Path $seedDir 'web-search.json')
    '{"mcpServers":{"unixOnly":{"command":"unix"}}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    '{"globalConcurrencyLimit":7}' | Set-Content (Join-Path $seedDir 'subagent-config.json')
    '{"mcpServers":{"windowsOnly":{"command":"windows"}}}' | Set-Content (Join-Path $windowsSeedDir 'mcp.json')
    '{"servers":{"vtsls":{"command":["vtsls","--stdio"]}}}' | Set-Content (Join-Path $windowsSeedDir 'pi-lsp.json')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    New-Item -ItemType Directory -Force -Path $extensionDir | Out-Null
    'stale' | Set-Content (Join-Path $extensionDir 'caveman-default.js')
    'stale' | Set-Content (Join-Path $extensionDir 'windows-exit.js')
    'stale' | Set-Content (Join-Path $extensionDir 'ponytail-default.js')

    SyncPiConfigs

    $settings = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $keybindings = Join-Path $env:USERPROFILE '.pi\agent\keybindings.json'
    $webSearch = Join-Path $env:USERPROFILE '.pi\web-search.json'
    $mcp = Join-Path $env:USERPROFILE '.pi\agent\mcp.json'
    $subagent = Join-Path $env:USERPROFILE '.pi\agent\extensions\subagent\config.json'
    $lsp = Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    $baseDir = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    Assert-FileExists $settings
    Assert-FileExists $keybindings
    Assert-FileExists $webSearch
    Assert-FileExists $mcp
    Assert-FileExists $subagent
    Assert-FileExists $lsp
    Assert-FileExists (Join-Path $baseDir 'settings.json')
    Assert-FileExists (Join-Path $baseDir 'keybindings.json')
    Assert-FileExists (Join-Path $baseDir 'web-search.json')
    Assert-FileExists (Join-Path $baseDir 'mcp.json')
    Assert-FileExists (Join-Path $baseDir 'subagent-config.json')
    $keys = Get-Content -Raw $keybindings | ConvertFrom-Json
    Assert-Equals 0 @($keys.'app.model.cycleForward').Count
    Assert-Equals 0 @($keys.'app.model.cycleBackward').Count
    Assert-Equals 'none' (Get-Content -Raw $webSearch | ConvertFrom-Json).workflow
    Assert-Contains (Get-Content -Raw $mcp) '"windowsOnly"'
    Assert-False ((Get-Content -Raw $mcp) -like '*unixOnly*') 'Windows should deploy Windows MCP seed'
    Assert-Contains (Get-Content -Raw $lsp) '"vtsls"'
    Assert-FileExists (Join-Path $extensionDir 'codex-status.js')
    Assert-False (Test-Path (Join-Path $extensionDir 'windows-exit.js')) 'Retired exit alias remains'
    Assert-False (Test-Path (Join-Path $extensionDir 'caveman-default.js')) 'Obsolete Caveman hook remains'
    Assert-False (Test-Path (Join-Path $extensionDir 'ponytail-default.js')) 'Obsolete Ponytail hook remains'
    Assert-False ([bool](Get-Item $settings).LinkType) 'Pi settings should stay writable'
}

function Assert-NoPiConfigStagingFiles($Destination) {
    $parent = Split-Path $Destination -Parent
    $leaf = Split-Path $Destination -Leaf
    Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.tmp.*" -Force -ErrorAction SilentlyContinue).Count
    Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.backup.*" -Force -ErrorAction SilentlyContinue).Count
}

function test_syncpiconfigs_rejects_overlapping_sync {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:NestedPiConfigSyncAttempted = $false
    $script:NestedPiConfigSyncFailure = $null
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if (-not $script:NestedPiConfigSyncAttempted -and $LiteralPath -eq $paths.Source -and $Destination -like '*.tmp.*') {
            $script:NestedPiConfigSyncAttempted = $true
            try {
                SyncPiConfigs
            } catch {
                $script:NestedPiConfigSyncFailure = $_.Exception.Message
            }
        }
        if ($null -eq $ErrorAction) {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
        } else {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
        }
    }

    SyncPiConfigs

    $lockPath = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\sync.lock'
    Assert-True $script:NestedPiConfigSyncAttempted 'nested sync should be attempted'
    Assert-Contains $script:NestedPiConfigSyncFailure 'Pi config sync lock unavailable'
    Assert-Contains $script:NestedPiConfigSyncFailure $lockPath
}

function test_syncpiconfigs_rejects_destination_change_before_commit {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:PiConfigDestinationChanged = $false
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($null -eq $ErrorAction) {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
        } else {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
        }
        if (-not $script:PiConfigDestinationChanged -and $LiteralPath -eq $paths.Source -and $Destination -like "$($paths.Target).tmp.*") {
            $script:PiConfigDestinationChanged = $true
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
        }
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'Pi subagent config destination changed during sync'
    Assert-Contains $failure $paths.Target
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $paths.Target).Trim())
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
    Assert-NoPiConfigStagingFiles $paths.Base
}

function test_syncpiconfigs_rejects_source_change_between_staged_copies {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:PiConfigSourceCopies = 0
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($null -eq $ErrorAction) {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
        } else {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
        }
        if ($LiteralPath -eq $paths.Source -and $Destination -like '*.tmp.*') {
            $script:PiConfigSourceCopies++
            if ($script:PiConfigSourceCopies -eq 1) {
                '{"globalConcurrencyLimit":8}' | Set-Content -LiteralPath $paths.Source
            }
        }
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'Pi subagent config source changed during sync'
    Assert-Contains $failure $paths.Source
    Assert-Equals 2 $script:PiConfigSourceCopies
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
    Assert-NoPiConfigStagingFiles $paths.Base
}

function test_syncpiconfigs_staging_failure_preserves_regular_subagent_target {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    $script:PiConfigFailureInjected = $false
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        if ($LiteralPath -eq $paths.Source -and $Destination -like "$($paths.Target).tmp.*") {
            $script:PiConfigFailureInjected = $true
            'partial' | Set-Content -LiteralPath $Destination
            throw 'simulated staging failure'
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }

    Assert-Throws { SyncPiConfigs }

    Assert-True $script:PiConfigFailureInjected 'target staging failure should be injected'
    Assert-False ([bool](Get-Item -LiteralPath $paths.Target -Force).LinkType) 'regular target should remain regular'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
}

function test_syncpiconfigs_staging_failure_preserves_linked_subagent_base {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    $external = Join-Path $script:_TestTmp.FullName 'external-base.json'
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $external
    New-Item -ItemType SymbolicLink -Path $paths.Base -Target $external | Out-Null
    $script:PiConfigFailureInjected = $false
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        if ($LiteralPath -eq $paths.Source -and $Destination -like "$($paths.Base).tmp.*") {
            $script:PiConfigFailureInjected = $true
            'partial' | Set-Content -LiteralPath $Destination
            throw 'simulated staging failure'
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }

    Assert-Throws { SyncPiConfigs }

    Assert-True $script:PiConfigFailureInjected 'base staging failure should be injected'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-True ([bool](Get-Item -LiteralPath $paths.Base -Force).LinkType) 'linked base should remain linked'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $external | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
    Assert-NoPiConfigStagingFiles $paths.Base
}

function test_syncpiconfigs_replacement_failure_preserves_regular_subagent_target {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    $script:PiConfigFailureInjected = $false
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            $script:PiConfigFailureInjected = $true
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    Assert-Throws { SyncPiConfigs }

    Assert-True $script:PiConfigFailureInjected 'target replacement failure should be injected'
    Assert-False ([bool](Get-Item -LiteralPath $paths.Target -Force).LinkType) 'regular target should remain regular'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
    Assert-NoPiConfigStagingFiles $paths.Base
}

function test_syncpiconfigs_replacement_failure_preserves_linked_subagent_base {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    $external = Join-Path $script:_TestTmp.FullName 'external-base.json'
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $external
    New-Item -ItemType SymbolicLink -Path $paths.Base -Target $external | Out-Null
    $script:PiConfigFailureInjected = $false
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            $script:PiConfigFailureInjected = $true
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    Assert-Throws { SyncPiConfigs }

    Assert-True $script:PiConfigFailureInjected 'base replacement failure should be injected'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-True ([bool](Get-Item -LiteralPath $paths.Base -Force).LinkType) 'linked base should remain linked'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $external | ConvertFrom-Json).globalConcurrencyLimit
    Assert-NoPiConfigStagingFiles $paths.Target
    Assert-NoPiConfigStagingFiles $paths.Base
}

function test_syncpiconfigs_reports_operation_rollback_and_temp_cleanup_failures {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            throw 'simulated replacement failure'
        }
        if ($LiteralPath -like "$($paths.Target).backup.*" -and $Destination -eq $paths.Target) {
            throw 'simulated backup restoration failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*") { throw 'simulated temp deletion failure' }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'simulated replacement failure'
    Assert-Contains $failure 'simulated backup restoration failure'
    Assert-Contains $failure 'simulated temp deletion failure'
    Assert-False (Test-Path -LiteralPath $paths.Target) 'failed restoration should leave destination absent rather than partial'
    $backups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    Assert-Equals 1 $backups.Count
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $backups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_reports_all_rollback_failures_and_recovery_paths {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:FailedTargetBackup = $null
    $script:FailedBaseBackup = $null
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            throw 'simulated base replacement failure'
        }
        if ($LiteralPath -like "$($paths.Base).backup.*" -and $Destination -eq $paths.Base) {
            $script:FailedBaseBackup = $LiteralPath
            throw 'simulated base backup restoration failure'
        }
        if ($LiteralPath -like "$($paths.Target).backup.*" -and $Destination -eq $paths.Target) {
            $script:FailedTargetBackup = $LiteralPath
            throw 'simulated target backup restoration failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'simulated base backup restoration failure'
    Assert-Contains $failure 'simulated target backup restoration failure'
    Assert-Contains $failure $script:FailedBaseBackup
    Assert-Contains $failure $script:FailedTargetBackup
    Assert-False (Test-Path -LiteralPath $paths.Target) 'failed target restoration should leave target absent'
    Assert-False (Test-Path -LiteralPath $paths.Base) 'failed base restoration should leave base absent'
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    $baseBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Equals 1 $baseBackups.Count
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $baseBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_continues_rollback_after_one_backup_restoration_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            throw 'simulated base replacement failure'
        }
        if ($LiteralPath -like "$($paths.Base).backup.*" -and $Destination -eq $paths.Base) {
            throw 'simulated base backup restoration failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'simulated base backup restoration failure'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-False (Test-Path -LiteralPath $paths.Base) 'failed restoration should leave base absent'
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    $baseBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force)
    Assert-Equals 0 $targetBackups.Count
    Assert-Equals 1 $baseBackups.Count
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $baseBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    foreach ($destination in $paths.Target, $paths.Base) {
        $parent = Split-Path $destination -Parent
        $leaf = Split-Path $destination -Leaf
        Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.tmp.*" -Force -ErrorAction SilentlyContinue).Count
    }
}

function test_syncpiconfigs_reports_later_rollback_failure_after_first_restoration_succeeds {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:FailedPiConfigBackup = $null
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            throw 'simulated base replacement failure'
        }
        if ($LiteralPath -like "$($paths.Target).backup.*" -and $Destination -eq $paths.Target) {
            $script:FailedPiConfigBackup = $LiteralPath
            throw "simulated target backup restoration failure: $LiteralPath"
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'Pi subagent config rollback failed after'
    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'simulated target backup restoration failure'
    Assert-Contains $failure $script:FailedPiConfigBackup
    Assert-False (Test-Path -LiteralPath $paths.Target) 'failed later restoration should leave target absent'
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    $baseBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Equals $script:FailedPiConfigBackup $targetBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 $baseBackups.Count
    foreach ($destination in $paths.Target, $paths.Base) {
        $parent = Split-Path $destination -Parent
        $leaf = Split-Path $destination -Leaf
        Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.tmp.*" -Force -ErrorAction SilentlyContinue).Count
    }
}

function test_syncpiconfigs_rollback_preserves_concurrent_destination_after_failed_install {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
            throw 'simulated target replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated target replacement failure'
    Assert-Contains $failure 'concurrently modified destination'
    Assert-Contains $failure $paths.Target
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $paths.Target).Trim())
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Contains $failure $targetBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force).Count
}

function test_syncpiconfigs_rollback_preserves_concurrently_replaced_installed_destination {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
            throw 'simulated base replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'concurrently modified destination'
    Assert-Contains $failure $paths.Target
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $paths.Target).Trim())
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    $baseBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Contains $failure $targetBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 $baseBackups.Count
    foreach ($destination in $paths.Target, $paths.Base) {
        $parent = Split-Path $destination -Parent
        $leaf = Split-Path $destination -Leaf
        Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.tmp.*" -Force -ErrorAction SilentlyContinue).Count
    }
}

function test_syncpiconfigs_reports_quarantined_content_when_restore_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    $script:FailedRollbackPath = $null
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
            throw 'simulated target replacement failure'
        }
        if ($LiteralPath -like "$($paths.Target).rollback.*" -and $Destination -eq $paths.Target) {
            $script:FailedRollbackPath = $LiteralPath
            throw 'simulated concurrent content restoration failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated target replacement failure'
    Assert-Contains $failure 'simulated concurrent content restoration failure'
    Assert-Contains $failure $script:FailedRollbackPath
    Assert-False (Test-Path -LiteralPath $paths.Target) 'failed concurrent-content restoration should leave target absent'
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $script:FailedRollbackPath).Trim())
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Contains $failure $targetBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_rollback_preserves_destination_created_after_quarantine {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            throw 'simulated base replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }
    $script:ConcurrentPiConfigCreated = $false
    Set-CommandMock 'Get-FileHash' {
        param($LiteralPath, $Algorithm)
        if (-not $script:ConcurrentPiConfigCreated -and $LiteralPath -like "$($paths.Target).rollback.*") {
            $script:ConcurrentPiConfigCreated = $true
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
        }
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-True $script:ConcurrentPiConfigCreated 'concurrent destination should be created during rollback validation'
    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'concurrently created destination'
    Assert-Contains $failure $paths.Target
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $paths.Target).Trim())
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Contains $failure $targetBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_rollback_preserves_concurrently_replaced_new_destination {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":88}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*" -and $Destination -eq $paths.Base) {
            'concurrent target content' | Set-Content -LiteralPath $paths.Target
            throw 'simulated base replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    }

    Assert-Contains $failure 'simulated base replacement failure'
    Assert-Contains $failure 'concurrently modified destination'
    Assert-Contains $failure $paths.Target
    Assert-Contains $failure 'no recovery backup exists'
    Assert-Equals 'concurrent target content' ((Get-Content -Raw -LiteralPath $paths.Target).Trim())
    Assert-Equals 88 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force).Count
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force).Count
    foreach ($destination in $paths.Target, $paths.Base) {
        $parent = Split-Path $destination -Parent
        $leaf = Split-Path $destination -Leaf
        Assert-Equals 0 @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.tmp.*" -Force -ErrorAction SilentlyContinue).Count
    }
}

function test_syncpiconfigs_rollback_does_not_delete_uninstalled_destination {
    $paths = Initialize-TestPiConfigSeeds
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            New-Item -ItemType Directory -Force -Path (Split-Path $paths.Base -Parent) | Out-Null
            'concurrent content' | Set-Content -LiteralPath $paths.Base
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }

    Assert-Throws { SyncPiConfigs }

    Assert-FileExists $paths.Base
    Assert-Equals 'concurrent content' ((Get-Content -Raw -LiteralPath $paths.Base).Trim())
}

function test_syncpiconfigs_reports_operation_and_temp_cleanup_failure_after_successful_rollback {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*") { throw 'simulated temp deletion failure' }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'simulated replacement failure'
    Assert-Contains $failure 'simulated temp deletion failure'
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force).Count
}

function test_syncpiconfigs_continues_temp_cleanup_after_one_deletion_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }
    $script:FailedPiConfigTemp = $null
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*") {
            $script:FailedPiConfigTemp = $LiteralPath
            throw "simulated temp deletion failure: $LiteralPath"
        }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'Pi subagent config cleanup failed after'
    Assert-Contains $failure 'simulated replacement failure'
    Assert-Contains $failure 'simulated temp deletion failure'
    Assert-Contains $failure $script:FailedPiConfigTemp
    $targetTemps = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.tmp.*' -Force)
    $baseTemps = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.tmp.*' -Force)
    Assert-Equals 1 $targetTemps.Count
    Assert-Equals $script:FailedPiConfigTemp $targetTemps[0].FullName
    Assert-Equals 0 $baseTemps.Count
}

function test_syncpiconfigs_retains_only_later_temp_when_second_deletion_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).tmp.*" -and $Destination -eq $paths.Target) {
            throw 'simulated replacement failure'
        }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
    }
    $script:FailedPiConfigTemp = $null
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).tmp.*") {
            $script:FailedPiConfigTemp = $LiteralPath
            throw "simulated base temp deletion failure: $LiteralPath"
        }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'Pi subagent config cleanup failed after'
    Assert-Contains $failure 'simulated replacement failure'
    Assert-Contains $failure 'simulated base temp deletion failure'
    Assert-Contains $failure $script:FailedPiConfigTemp
    $targetTemps = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.tmp.*' -Force)
    $baseTemps = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.tmp.*' -Force)
    Assert-Equals 0 $targetTemps.Count
    Assert-Equals 1 $baseTemps.Count
    Assert-Equals $script:FailedPiConfigTemp $baseTemps[0].FullName
}

function test_syncpiconfigs_reports_backup_cleanup_failure_and_keeps_recovery_backup {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base
    $script:FailedTargetBackup = $null
    $script:FailedBaseBackup = $null
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).backup.*") {
            $script:FailedTargetBackup = $LiteralPath
            throw 'simulated target backup deletion failure'
        }
        if ($LiteralPath -like "$($paths.Base).backup.*") {
            $script:FailedBaseBackup = $LiteralPath
            throw 'simulated base backup deletion failure'
        }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'Pi subagent config cleanup failed'
    Assert-Contains $failure 'simulated target backup deletion failure'
    Assert-Contains $failure 'simulated base backup deletion failure'
    Assert-Contains $failure $script:FailedTargetBackup
    Assert-Contains $failure $script:FailedBaseBackup
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    foreach ($destination in $paths.Target, $paths.Base) {
        $parent = Split-Path $destination -Parent
        $leaf = Split-Path $destination -Leaf
        $backups = @(Get-ChildItem -LiteralPath $parent -Filter "$leaf.backup.*" -Force)
        Assert-Equals 1 $backups.Count
        Assert-Equals 99 (Get-Content -Raw -LiteralPath $backups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    }
}

function test_syncpiconfigs_continues_backup_cleanup_after_one_deletion_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base
    $script:FailedPiConfigBackup = $null
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Target).backup.*") {
            $script:FailedPiConfigBackup = $LiteralPath
            throw "simulated target backup deletion failure: $LiteralPath"
        }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'Pi subagent config cleanup failed'
    Assert-Contains $failure 'simulated target backup deletion failure'
    Assert-Contains $failure $script:FailedPiConfigBackup
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    Assert-Equals 1 $targetBackups.Count
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $targetBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force).Count
}

function test_syncpiconfigs_retains_only_later_backup_when_second_deletion_fails {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base
    $script:FailedPiConfigBackup = $null
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if ($LiteralPath -like "$($paths.Base).backup.*") {
            $script:FailedPiConfigBackup = $LiteralPath
            throw "simulated base backup deletion failure: $LiteralPath"
        }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
    }

    $failure = $null
    try {
        SyncPiConfigs
    } catch {
        $failure = $_.Exception.Message
    } finally {
        Clear-CommandMock 'Remove-Item'
    }

    Assert-Contains $failure 'Pi subagent config cleanup failed'
    Assert-Contains $failure 'simulated base backup deletion failure'
    Assert-Contains $failure $script:FailedPiConfigBackup
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
    $targetBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Target -Parent) -Filter 'config.json.backup.*' -Force)
    $baseBackups = @(Get-ChildItem -LiteralPath (Split-Path $paths.Base -Parent) -Filter 'subagent-config.json.backup.*' -Force)
    Assert-Equals 0 $targetBackups.Count
    Assert-Equals 1 $baseBackups.Count
    Assert-Equals $script:FailedPiConfigBackup $baseBackups[0].FullName
    Assert-Equals 99 (Get-Content -Raw -LiteralPath $baseBackups[0].FullName | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_skips_unchanged_regular_subagent_destinations {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    Copy-Item -LiteralPath $paths.Source -Destination $paths.Target
    Copy-Item -LiteralPath $paths.Source -Destination $paths.Base
    $script:PiConfigMoves = @()
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        $script:PiConfigMoves += $Destination
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }

    SyncPiConfigs

    Assert-False ($script:PiConfigMoves -contains $paths.Target) 'unchanged regular target should not be replaced'
    Assert-False ($script:PiConfigMoves -contains $paths.Base) 'unchanged regular base should not be replaced'
}

function test_syncpiconfigs_replaces_changed_regular_subagent_destinations {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Base

    SyncPiConfigs

    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_creates_missing_subagent_destinations {
    $paths = Initialize-TestPiConfigSeeds

    SyncPiConfigs

    Assert-FileExists $paths.Target
    Assert-FileExists $paths.Base
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_replaces_linked_subagent_destinations {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent), (Split-Path $paths.Base -Parent) | Out-Null
    $externalTarget = Join-Path $script:_TestTmp.FullName 'external-target.json'
    $externalBase = Join-Path $script:_TestTmp.FullName 'external-base.json'
    Copy-Item -LiteralPath $paths.Source -Destination $externalTarget
    Copy-Item -LiteralPath $paths.Source -Destination $externalBase
    New-Item -ItemType SymbolicLink -Path $paths.Target -Target $externalTarget | Out-Null
    New-Item -ItemType SymbolicLink -Path $paths.Base -Target $externalBase | Out-Null

    SyncPiConfigs

    Assert-False ([bool](Get-Item -LiteralPath $paths.Target -Force).LinkType) 'linked target should become a regular file'
    Assert-False ([bool](Get-Item -LiteralPath $paths.Base -Force).LinkType) 'linked base should become a regular file'
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Target | ConvertFrom-Json).globalConcurrencyLimit
    Assert-Equals 7 (Get-Content -Raw -LiteralPath $paths.Base | ConvertFrom-Json).globalConcurrencyLimit
}

function test_syncpiconfigs_skips_only_unchanged_regular_direct_copies {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $windowsSeedDir = Join-Path $script:DotfilesDir 'config\windows\ai\pi'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    New-Item -ItemType Directory -Force -Path $seedDir, $windowsSeedDir, $extensionDir | Out-Null

    foreach ($name in 'settings.json', 'keybindings.json', 'web-search.json', 'subagent-config.json') {
        '{}' | Set-Content -LiteralPath (Join-Path $seedDir $name)
    }
    '{}' | Set-Content -LiteralPath (Join-Path $windowsSeedDir 'mcp.json')
    'same lsp' | Set-Content -LiteralPath (Join-Path $windowsSeedDir 'pi-lsp.json')
    'same lsp' | Set-Content -LiteralPath (Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json')
    'linked replacement' | Set-Content -LiteralPath (Join-Path $seedDir 'codex-status.js')
    $external = Join-Path $script:_TestTmp.FullName 'external-codex-status.js'
    'external' | Set-Content -LiteralPath $external
    New-Item -ItemType SymbolicLink -Path (Join-Path $extensionDir 'codex-status.js') -Target $external | Out-Null

    $script:PiConfigCopies = @()
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force)
        $script:PiConfigCopies += $Destination
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }

    SyncPiConfigs

    $lsp = Join-Path $env:USERPROFILE '.pi\agent\pi-lsp.json'
    $linkedExtension = Join-Path $extensionDir 'codex-status.js'
    Assert-Equals 0 @($script:PiConfigCopies | Where-Object { $_ -like "$lsp.tmp.*" }).Count
    Assert-Equals 1 @($script:PiConfigCopies | Where-Object { $_ -like "$linkedExtension.tmp.*" }).Count
    Assert-False ([bool](Get-Item -LiteralPath $linkedExtension -Force).LinkType) 'linked extension should become a regular file'
    Assert-Equals 'linked replacement' ((Get-Content -Raw -LiteralPath $linkedExtension).Trim())
    Assert-Equals 'external' ((Get-Content -Raw -LiteralPath $external).Trim())
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
    '{"app.model.cycleForward":[],"app.model.cycleBackward":[]}' | Set-Content (Join-Path $seedDir 'keybindings.json')
    '{"workflow":"none"}' | Set-Content (Join-Path $seedDir 'web-search.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    '{"globalConcurrencyLimit":7}' | Set-Content (Join-Path $seedDir 'subagent-config.json')
    '{"mcpServers":{}}' | Set-Content (Join-Path $windowsSeedDir 'mcp.json')
    '{"servers":{"vtsls":{"command":["vtsls","--stdio"]}}}' | Set-Content (Join-Path $windowsSeedDir 'pi-lsp.json')
    '{"servers":{"nil":{"command":["nil"]}}}' | Set-Content (Join-Path $targetDir 'pi-lsp.json')
    '{"globalConcurrencyLimit":99}' | Set-Content (Join-Path $subagentDir 'config.json')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
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
