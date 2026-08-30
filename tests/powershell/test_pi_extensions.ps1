# Windows integrity-locked Pi extension installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalArchitecture = $env:PROCESSOR_ARCHITECTURE
    $script:OriginalExpandWindowsTarArchive = (Get-Command Expand-WindowsTarArchive).ScriptBlock
    $script:PythonLauncher = (Get-Command py).Source
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'node', 'npm', 'py', 'pi', 'tar', 'Invoke-WebRequest', 'Copy-Item') {
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
        betterSqlite3 = @{ version = '13.0.3' }
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

  pi.on("session_shutdown", async (event, ctx) => {
    if (!config.flushOnShutdown || event.reason === "reload") return;
    await measureLifecycle("shutdown.flush", () => flush(ctx, undefined, 10000));
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

const child = spawn(command, args, {
  detached: process.platform !== "win32",
  stdio: ["ignore", "pipe", "pipe"],
});

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
    Assert-Equals 4 @($settings.packages).Count
    Assert-Equals 4 @($package.dependencies.PSObject.Properties).Count
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains 'pi-mcp-extension') 'Pi MCP extension should be removed'
    Assert-False ($settings.packages -like '*pi-mcp-extension*') 'Pi MCP package path should be removed'
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@ff-labs/pi-fff') 'native FFF MCP should remain absent'
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
        Set-CommandMock 'pi' { $calls.Add('pi update --extensions'); $global:LASTEXITCODE = 0 }
        InstallAi -Update
        Assert-Equals 'InstallFnm,InstallCodex,SyncCodexConfig,InstallCodebaseMemory,InstallPi,InstallPiLanguageServers,InstallPiExtensions,SyncPiConfigs,pi update --extensions,SyncAiInstructions,InstallAiSkills' ($calls -join ',') 'InstallAi collaborators should run in the safe order'
    } finally {
        foreach ($name in $names) { Set-FunctionMock $name $original[$name] }
    }
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
    if (-not $IsWindows) { Skip-Test 'Windows-only bundled prebuild installation'; return }
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'repo'
    New-PiExtensionTestFixture $script:DotfilesDir
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $script:NpmArgs = ''
    $pinsPath = Join-Path $script:DotfilesDir 'packages\pi-extensions-release.json'

    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -in @('node', 'npm', 'py')) { return [pscustomobject]@{ Source = "mock-$Name" } }
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
        $hermesDir = Join-Path $prefix 'node_modules\pi-hermes-memory'
        $betterDir = Join-Path $prefix 'node_modules\better-sqlite3'
        $prebuilds = Join-Path $betterDir 'prebuilds'
        New-Item -ItemType Directory -Force -Path $packageDir, $betterDir, $prebuilds | Out-Null
        Write-PiHermesUnpatchedFixture $hermesDir
        '{"name":"example-extension","version":"1.2.3"}' | Set-Content -LiteralPath (Join-Path $packageDir 'package.json') -Encoding ascii
        '{"name":"better-sqlite3","version":"13.0.3"}' | Set-Content -LiteralPath (Join-Path $betterDir 'package.json') -Encoding ascii
        'native' | Set-Content -LiteralPath (Join-Path $prebuilds 'win32-x64.node') -Encoding ascii
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'py' {
        & $script:PythonLauncher -3.14 $args[1] $args[2]
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    InstallPiExtensions 6>&1 | Out-Null

    Assert-Contains $script:NpmArgs 'ci --prefix'
    Assert-Contains $script:NpmArgs '--ignore-scripts'
    Assert-Contains $script:NpmArgs '--legacy-peer-deps'
    $stagedHermes = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$((Get-Content -Raw $pinsPath | ConvertFrom-Json).releaseId)\node_modules\pi-hermes-memory\src\handlers"
    Assert-Contains (Get-Content -Raw (Join-Path $stagedHermes 'session-flush.ts')) 'execDetachedChildPrompt'
    Assert-Contains (Get-Content -Raw (Join-Path $stagedHermes 'child-process-watchdog.mjs')) 'windowsHide: true'
    $pins = Get-Content -Raw $pinsPath | ConvertFrom-Json
    $release = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$($pins.releaseId)"
    Assert-True (Test-PiExtensionsRelease $release $pins) 'immutable extension release should validate'

    $tamperCases = @(
        @{ Path = Join-Path $release 'node_modules\pi-hermes-memory\src\handlers\session-flush.ts'; Marker = 'execDetachedChildPrompt' },
        @{ Path = Join-Path $release 'node_modules\pi-hermes-memory\src\handlers\pi-child-process.ts'; Marker = '"--cleanup-dir"' },
        @{ Path = Join-Path $release 'node_modules\pi-hermes-memory\src\handlers\child-process-watchdog.mjs'; Marker = 'cleanupPromptDirectory' },
        @{ Path = Join-Path $release 'node_modules\pi-hermes-memory\src\handlers\child-process-watchdog.mjs'; Marker = 'windowsHide: true' }
    )
    foreach ($case in $tamperCases) {
        $original = Get-Content -Raw -LiteralPath $case.Path
        $tampered = $original.Replace($case.Marker, 'REMOVED_PATCH_MARKER')
        Set-Content -LiteralPath $case.Path -Value $tampered -Encoding ascii -NoNewline
        Assert-False (Test-PiExtensionsRelease $release $pins) "release missing $($case.Marker) must fail validation"
        Set-Content -LiteralPath $case.Path -Value $original -Encoding ascii -NoNewline
        Assert-True (Test-PiExtensionsRelease $release $pins) "restored $($case.Marker) release should validate"
    }
}
