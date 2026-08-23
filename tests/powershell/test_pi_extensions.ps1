# Windows integrity-locked Pi extension installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalArchitecture = $env:PROCESSOR_ARCHITECTURE
    $script:OriginalExpandWindowsTarArchive = (Get-Command Expand-WindowsTarArchive).ScriptBlock
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'node', 'npm', 'py', 'tar', 'Invoke-WebRequest', 'Copy-Item') {
        Clear-CommandMock $command
    }
    $env:PROCESSOR_ARCHITECTURE = $script:OriginalArchitecture
    Set-FunctionMock 'Expand-WindowsTarArchive' $script:OriginalExpandWindowsTarArchive
    Clear-TestEnv
}

function Get-PiExtensionTestSha256($Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return Get-StreamSha256 $stream } finally { $stream.Dispose() }
}

function New-PiExtensionTestFixture($Root, [switch]$WrongLockHash) {
    $source = Join-Path $Root 'config\shared\ai\pi\extensions'
    $packages = Join-Path $Root 'packages'
    $scripts = Join-Path $Root 'scripts'
    New-Item -ItemType Directory -Force -Path $source, $packages, $scripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepoDir 'scripts\patch_pi_mcp_background.py') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path $script:RepoDir 'scripts\patch_pi_hermes_background_flush.py') -Destination $scripts
    '{"name":"fixture","private":true,"version":"1.0.0","dependencies":{"example-extension":"1.2.3"}}' |
        Set-Content -LiteralPath (Join-Path $source 'package.json') -Encoding ascii
    '{"name":"fixture","lockfileVersion":3,"packages":{"":{"dependencies":{"example-extension":"1.2.3"}},"node_modules/example-extension":{"version":"1.2.3","resolved":"https://registry.npmjs.org/example-extension/-/example-extension-1.2.3.tgz","integrity":"sha512-test"}}}' |
        Set-Content -LiteralPath (Join-Path $source 'package-lock.json') -Encoding ascii
    $lockHash = Get-PiExtensionTestSha256 (Join-Path $source 'package-lock.json')
    if ($WrongLockHash) { $lockHash = '0' * 64 }
    @{
        releaseId = $lockHash
        node = @{ version = '24.18.1'; abi = '137' }
        betterSqlite3 = @{
            version = '12.11.1'
            assets = @{
                'windows-x64' = @{ file = 'better-sqlite3-test-win32-x64.tar.gz'; sha256 = 'a' * 64; hash = 'sha256-test' }
                'windows-arm64' = @{ file = 'better-sqlite3-test-win32-arm64.tar.gz'; sha256 = 'b' * 64; hash = 'sha256-test' }
            }
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $packages 'pi-extensions-release.json') -Encoding ascii
}

function Write-PiHermesUnpatchedFixture($Root) {
    $handlers = Join-Path $Root 'src\handlers'
    New-Item -ItemType Directory -Force -Path $handlers | Out-Null
    @'
import { execChildPrompt, resolveChildPiModel } from "./pi-child-process.js";

  async function flush(
    ctx: Pick<ExtensionContext, "sessionManager" | "model" | "modelRegistry" | "cwd">,
    signal?: AbortSignal,
    timeoutMs = 30000,
  ): Promise<void> {
    if (userTurnCount < config.flushMinTurns) return;
    if (usesDirectTransport(config)) {
      try {
        const directResult = await runDirect();
        if (directResult.ok) return;
      } catch {}
    }
    try {
      await execChildPrompt(pi, flushMessage, config, {
        cwd: ctx.cwd,
        model: resolveChildPiModel(ctx.model),
        signal,
        timeoutMs,
      });
    } catch {}
  }

  pi.on("session_shutdown", async (_event, ctx) => {
    if (!config.flushOnShutdown) return;
    await flush(ctx, undefined, 10000);
  });
'@ | Set-Content -LiteralPath (Join-Path $handlers 'session-flush.ts') -Encoding ascii
    @'
import { existsSync, readFileSync, readdirSync } from "node:fs";
import * as fs from "node:fs/promises";

export async function execChildPrompt(
  pi: Pick<ExtensionAPI, "exec">,
'@ | Set-Content -LiteralPath (Join-Path $handlers 'pi-child-process.ts') -Encoding ascii
    @'
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";

const [timeoutValue, cancellationPath, command, ...args] = process.argv.slice(2);
const timeoutMs = Number(timeoutValue);

if (!cancellationPath || !command || !Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  process.stderr.write("pi-hermes-memory watchdog: invalid invocation\n");
  process.exit(2);
}

child.once("error", (error) => {
  clearTimeout(timeout);
  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);
  process.stderr.write(`pi-hermes-memory watchdog: ${error.message}\n`);
  process.exitCode = timedOut ? 124 : cancelled ? 143 : 127;
});

child.once("close", (code, signal) => {
  clearTimeout(timeout);
  if (cancellationPoll) clearInterval(cancellationPoll);
  if (forceTimer) clearTimeout(forceTimer);
  if (timedOut) {
    process.exitCode = 124;
  } else if (cancelled) {
    process.exitCode = 143;
  } else if (typeof code === "number") {
    process.exitCode = code;
  } else {
    process.exitCode = signal === "SIGTERM" ? 143 : 1;
  }
});
'@ | Set-Content -LiteralPath (Join-Path $handlers 'child-process-watchdog.mjs') -Encoding ascii
    '{"name":"pi-hermes-memory","version":"0.9.5"}' | Set-Content -LiteralPath (Join-Path $Root 'package.json') -Encoding ascii
}

function test_pi_extension_sources_are_local_and_match_locked_release {
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\pi-extensions-release.json') | ConvertFrom-Json
    $settings = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\ai\pi\settings.json') | ConvertFrom-Json
    $package = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package.json') | ConvertFrom-Json
    $lock = Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package-lock.json'

    Assert-Equals $pins.releaseId (Get-PiExtensionTestSha256 $lock)
    Assert-Equals 5 @($settings.packages).Count
    Assert-Equals 5 @($package.dependencies.PSObject.Properties).Count
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@ff-labs/pi-fff') 'native FFF MCP should replace npm adapter'
    Assert-False ($package.PSObject.Properties.Name -contains 'overrides') 'FFF npm overrides should be removed'
    foreach ($entry in $settings.packages) {
        $source = if ($entry -is [string]) { $entry } else { $entry.source }
        Assert-True $source.StartsWith("./locked-extensions/releases/$($pins.releaseId)/node_modules/") 'Pi extension should use locked local release'
    }
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@dietrichgebert/ponytail') 'Retired Ponytail package should remain absent'
    Assert-Equals 0 @($settings.packages | Where-Object {
        $source = if ($_ -is [string]) { $_ } else { $_.source }
        $source -like '*@dietrichgebert/ponytail*'
    }).Count
    Assert-Equals 0 @($settings.packages | Where-Object {
        $source = if ($_ -is [string]) { $_ } else { $_.source }
        $source -like '*@ff-labs/pi-fff*'
    }).Count
}


function test_installai_installs_pinned_node_before_ai_tools {
    $script:Dry = $false
    $calls = [Collections.Generic.List[string]]::new()
    $names = 'InstallFnm', 'InstallCodex', 'InstallCodebaseMemory', 'SyncCodexConfig', 'InstallPi', 'InstallPiLanguageServers', 'InstallPiExtensions', 'SyncPiConfigs', 'SyncAiInstructions', 'InstallAiSkills'
    $original = @{}
    try {
        foreach ($name in $names) {
            $original[$name] = (Get-Command $name).ScriptBlock
            Set-FunctionMock $name { $calls.Add($MyInvocation.MyCommand.Name) }
        }
        InstallAi
        Assert-Equals 'InstallFnm' $calls[0] 'pinned Node should install first'
        Assert-Equals 'InstallCodex' $calls[1] 'Codex should follow pinned Node'
        Assert-True ($calls.IndexOf('SyncCodexConfig') -lt $calls.IndexOf('InstallCodebaseMemory')) 'repo-owned Codex config should exist before codebase-memory runtime setup'
    } finally {
        foreach ($name in $names) { Set-FunctionMock $name $original[$name] }
    }
}

function test_installai_activates_locked_extensions_before_reconciliation {
    $definition = (Get-Command InstallAi).Definition
    $installIndex = $definition.IndexOf('InstallPiExtensions')
    $syncIndex = $definition.IndexOf('SyncPiConfigs')
    $updateIndex = $definition.IndexOf('pi update --extensions')

    Assert-True ($installIndex -ge 0 -and $installIndex -lt $syncIndex) 'locked release should exist before settings activation'
    Assert-True ($syncIndex -lt $updateIndex) 'local package settings should activate before Pi reconciliation'
}

function test_installpiextensions_rejects_lock_hash_mismatch_before_npm {
    Assert-True ([bool](Get-Command InstallPiExtensions -ErrorAction SilentlyContinue)) 'locked extension installer should exist'
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'repo'
    New-PiExtensionTestFixture $script:DotfilesDir -WrongLockHash
    $script:NpmCalled = $false
    Set-CommandMock 'npm' { $script:NpmCalled = $true; $global:LASTEXITCODE = 0 }

    Assert-Throws { InstallPiExtensions 6>&1 | Out-Null } 'lock mismatch should fail closed'
    Assert-False $script:NpmCalled 'npm should not run before lock validation'
}

function test_piextensionsrelease_validates_mcp_subagent_startup_patch {
    $definition = (Get-Command Test-PiExtensionsRelease).Definition

    Assert-Contains $definition 'if (process.env.PI_SUBAGENT_DEPTH) await eagerStartup;'
}

function test_piextensionsrelease_validates_hermes_background_flush_patch {
    $definition = (Get-Command Test-PiExtensionsRelease).Definition

    Assert-Contains $definition 'execDetachedChildPrompt'
    Assert-Contains $definition '"--cleanup-dir"'
}

function test_installpiextensions_applies_hermes_background_flush_patch_after_npm {
    $definition = (Get-Command InstallPiExtensions).Definition
    $npmIndex = $definition.IndexOf('npm ci --prefix')
    $patchIndex = $definition.IndexOf('patch_pi_hermes_background_flush.py')
    $publishIndex = $definition.IndexOf('Move-Item -LiteralPath $staging -Destination $release')

    Assert-True ($npmIndex -ge 0 -and $npmIndex -lt $patchIndex) 'Hermes patch should run after npm materializes sources'
    Assert-True ($patchIndex -lt $publishIndex) 'Hermes patch should run before immutable release publication'
}

function test_installpiextensions_hashes_staged_lock_while_read_locked {
    $definition = (Get-Command InstallPiExtensions).Definition
    $openIndex = $definition.IndexOf("Open(`$stagedLock")
    $hashIndex = $definition.IndexOf('Get-StreamSha256 $lockStream')
    $npmIndex = $definition.IndexOf('npm ci --prefix')

    Assert-True ($openIndex -ge 0 -and $openIndex -lt $hashIndex) 'staged lock should be held before hashing'
    Assert-True ($hashIndex -lt $npmIndex) 'locked hash should validate before npm'
    Assert-False ($definition -like '*Get-FileSha256 $stagedLock*') 'separate file hash would leave a pre-lock race'
}

function test_installpiextensions_rechecks_staged_lock_before_npm {
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'repo'
    New-PiExtensionTestFixture $script:DotfilesDir
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $script:NpmCalled = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -in @('node', 'npm', 'py', 'tar')) { return [pscustomobject]@{ Source = "mock-$Name" } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'node' {
        if ($args[0] -eq '--version') { 'v24.18.1' } else { '137' }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'Copy-Item' {
        Microsoft.PowerShell.Management\Copy-Item @args
        $destination = [string]$args[[Array]::IndexOf($args, '-Destination') + 1]
        '{}' | Set-Content -LiteralPath (Join-Path $destination 'package-lock.json') -Encoding ascii
    }
    Set-CommandMock 'npm' { $script:NpmCalled = $true; $global:LASTEXITCODE = 0 }

    Assert-Throws { InstallPiExtensions 6>&1 | Out-Null } 'staged lock mutation should fail closed'
    Assert-False $script:NpmCalled 'npm should not run after staged lock mutation'
}

function test_installpiextensions_uses_npm_ci_without_scripts_and_immutable_release {
    if (-not $IsWindows) { Skip-Test 'Windows-only native archive installation'; return }
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'repo'
    New-PiExtensionTestFixture $script:DotfilesDir
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $script:NpmArgs = ''
    $archiveText = 'verified better sqlite archive'
    $archiveFile = Join-Path $script:_TestTmp.FullName 'archive.bin'
    [IO.File]::WriteAllText($archiveFile, $archiveText)
    $archiveHash = Get-PiExtensionTestSha256 $archiveFile
    $pinsPath = Join-Path $script:DotfilesDir 'packages\pi-extensions-release.json'
    $pins = Get-Content -Raw $pinsPath | ConvertFrom-Json
    $pins.betterSqlite3.assets.'windows-x64'.sha256 = $archiveHash
    $pins | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pinsPath -Encoding ascii

    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -in @('node', 'npm', 'py', 'tar')) { return [pscustomobject]@{ Source = "mock-$Name" } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'node' {
        if ($args[0] -eq '--version') { 'v24.18.1' } else { '137' }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'npm' {
        $script:NpmArgs = $args -join ' '
        $prefix = $args[[Array]::IndexOf($args, '--prefix') + 1]
        $packageDir = Join-Path $prefix 'node_modules\example-extension'
        $mcpDir = Join-Path $prefix 'node_modules\pi-mcp-extension\src'
        $hermesDir = Join-Path $prefix 'node_modules\pi-hermes-memory'
        New-Item -ItemType Directory -Force -Path $packageDir, $mcpDir, (Join-Path $prefix 'node_modules\better-sqlite3') | Out-Null
        Write-PiHermesUnpatchedFixture $hermesDir
        '{"name":"example-extension","version":"1.2.3"}' | Set-Content -LiteralPath (Join-Path $packageDir 'package.json') -Encoding ascii
        '{"name":"better-sqlite3","version":"12.11.1"}' | Set-Content -LiteralPath (Join-Path $prefix 'node_modules\better-sqlite3\package.json') -Encoding ascii
        @'
    // Start all eager servers concurrently
    await Promise.allSettled(
      eagerServers.map(async ([name]) => {
        try {
          await manager.startServer(name, ctx.cwd);
        } catch (err) {
          const msg = err instanceof McpError ? err.userMessage : String(err);
          ctx.ui.notify(`pi-mcp: Failed to start ${name} — ${msg}`, "error");
        }
      }),
    );
'@ | Set-Content -LiteralPath (Join-Path $mcpDir 'index.ts') -Encoding utf8
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'py' {
        & python3 $args[1] $args[2]
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile)
        [IO.File]::WriteAllText($OutFile, $archiveText)
    }
    Set-FunctionMock 'Expand-WindowsTarArchive' {
        param($Archive, $Destination)
        $nativeDir = Join-Path $Destination 'build\Release'
        New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null
        'native' | Set-Content -LiteralPath (Join-Path $nativeDir 'better_sqlite3.node') -Encoding ascii
        $global:LASTEXITCODE = 0
    }

    InstallPiExtensions 6>&1 | Out-Null

    Assert-Contains $script:NpmArgs 'ci --prefix'
    Assert-Contains $script:NpmArgs '--ignore-scripts'
    Assert-Contains $script:NpmArgs '--legacy-peer-deps'
    $stagedMcp = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$((Get-Content -Raw $pinsPath | ConvertFrom-Json).releaseId)\node_modules\pi-mcp-extension\src\index.ts"
    Assert-Contains (Get-Content -Raw $stagedMcp) 'if (process.env.PI_SUBAGENT_DEPTH) await eagerStartup;'
    $stagedHermes = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$((Get-Content -Raw $pinsPath | ConvertFrom-Json).releaseId)\node_modules\pi-hermes-memory\src\handlers\session-flush.ts"
    Assert-Contains (Get-Content -Raw $stagedHermes) 'execDetachedChildPrompt'
    $pins = Get-Content -Raw $pinsPath | ConvertFrom-Json
    $release = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$($pins.releaseId)"
    Assert-True (Test-PiExtensionsRelease $release $pins) 'immutable extension release should validate'
}
