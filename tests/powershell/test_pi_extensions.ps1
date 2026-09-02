# Windows integrity-locked Pi extension installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalArchitecture = $env:PROCESSOR_ARCHITECTURE
    $script:OriginalExpandWindowsTarArchive = (Get-Command Expand-WindowsTarArchive).ScriptBlock
    $script:NodeLauncher = (Get-Command node).Source
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
    New-Item -ItemType Directory -Force -Path $source, $packages | Out-Null
    '{"name":"fixture","private":true,"version":"1.0.0","dependencies":{"example-extension":"1.2.3","pi-memory":"0.4.2"}}' |
        Set-Content -LiteralPath (Join-Path $source 'package.json') -Encoding ascii
    '{"name":"fixture","lockfileVersion":3,"packages":{"":{"dependencies":{"example-extension":"1.2.3","pi-memory":"0.4.2"}},"node_modules/example-extension":{"version":"1.2.3","resolved":"https://registry.npmjs.org/example-extension/-/example-extension-1.2.3.tgz","integrity":"sha512-test"},"node_modules/pi-memory":{"version":"0.4.2","resolved":"https://registry.npmjs.org/pi-memory/-/pi-memory-0.4.2.tgz","integrity":"sha512-test"}}}' |
        Set-Content -LiteralPath (Join-Path $source 'package-lock.json') -Encoding ascii
    $lockHash = Get-PiExtensionTestSha256 (Join-Path $source 'package-lock.json')
    if ($WrongLockHash) { $lockHash = '0' * 64 }
    @{
        releaseId = $lockHash
        node = @{ version = '24.18.1'; abi = '137' }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $packages 'pi-extensions-release.json') -Encoding ascii
}

function test_pi_extension_sources_are_local_and_match_locked_release {
    $pins = Get-Content -Raw (Join-Path $script:RepoDir 'packages\pi-extensions-release.json') | ConvertFrom-Json
    $settings = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\ai\pi\settings.json') | ConvertFrom-Json
    $package = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package.json') | ConvertFrom-Json
    $lock = Join-Path $script:RepoDir 'config\shared\ai\pi\extensions\package-lock.json'

    Assert-Equals $pins.releaseId (Get-PiExtensionTestSha256 $lock)
    Assert-Equals 2 @($settings.packages).Count
    Assert-Equals 2 @($package.dependencies.PSObject.Properties).Count
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@narumitw/pi-lsp') 'Pi LSP package should be removed'
    Assert-False ($settings.packages -like '*@narumitw/pi-lsp*') 'Pi LSP package path should be removed'
    Assert-False ((Get-Content -Raw $lock) -like '*node_modules/@narumitw/pi-lsp*') 'Pi LSP lock entry should be removed'
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains 'pi-mcp-extension') 'Pi MCP extension should be removed'
    Assert-False ($settings.packages -like '*pi-mcp-extension*') 'Pi MCP package path should be removed'
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@ff-labs/pi-fff') 'native FFF MCP should remain absent'
    Assert-False ($package.PSObject.Properties.Name -contains 'overrides') 'FFF npm overrides should be removed'
    foreach ($entry in $settings.packages) {
        $source = if ($entry -is [string]) { $entry } else { $entry.source }
        Assert-True $source.StartsWith("./locked-extensions/releases/$($pins.releaseId)/node_modules/") 'Pi extension should use locked local release'
    }
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains '@dietrichgebert/ponytail') 'Retired Ponytail package should remain absent'
    Assert-True ($package.dependencies.PSObject.Properties.Name -contains 'pi-memory') 'Lightweight Pi memory should be pinned'
    Assert-False ($package.dependencies.PSObject.Properties.Name -contains 'pi-hermes-memory') 'Hermes memory should be removed'
    Assert-False ((Get-Content -Raw (Join-Path $script:RepoDir 'dotfile.ps1')).Contains('patch_pi_memory_untrusted_context')) 'default pi-memory should remain unpatched'
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
    $names = 'InstallFnm', 'InstallCodex', 'RemoveCodebaseMemory', 'SyncCodexConfig', 'InstallPi', 'InstallPiLanguageServers', 'InstallPiExtensions', 'SyncPiConfigs', 'SyncAiInstructions', 'InstallAiSkills'
    $original = @{}
    try {
        foreach ($name in $names) {
            $original[$name] = (Get-Command $name).ScriptBlock
            Set-FunctionMock $name { $calls.Add($MyInvocation.MyCommand.Name) }
        }
        Set-CommandMock 'pi' { $calls.Add('pi update --extensions'); $global:LASTEXITCODE = 0 }
        InstallAi -Update
        Assert-Equals 'InstallFnm,InstallCodex,SyncCodexConfig,RemoveCodebaseMemory,InstallPi,InstallPiLanguageServers,InstallPiExtensions,SyncPiConfigs,pi update --extensions,SyncAiInstructions,InstallAiSkills' ($calls -join ',') 'InstallAi collaborators should run in the safe order'
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
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'repo'
    New-PiExtensionTestFixture $script:DotfilesDir
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $script:NpmArgs = ''
    $pinsPath = Join-Path $script:DotfilesDir 'packages\pi-extensions-release.json'

    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -in @('node', 'npm')) { return [pscustomobject]@{ Source = "mock-$Name" } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'node' {
        if ($args[0] -eq '--version') { 'v24.18.1' }
        elseif ($args[0] -eq '-p') { '137' }
        else { & $script:NodeLauncher @args }
        $global:LASTEXITCODE = 0
    }
    Set-CommandMock 'npm' {
        $script:NpmArgs = $args -join ' '
        $prefix = $args[[Array]::IndexOf($args, '--prefix') + 1]
        $packageDir = Join-Path $prefix 'node_modules\example-extension'
        $memoryDir = Join-Path $prefix 'node_modules\pi-memory'
        New-Item -ItemType Directory -Force -Path $packageDir, $memoryDir | Out-Null
        '{"name":"example-extension","version":"1.2.3"}' | Set-Content -LiteralPath (Join-Path $packageDir 'package.json') -Encoding ascii
        '{"name":"pi-memory","version":"0.4.2"}' | Set-Content -LiteralPath (Join-Path $memoryDir 'package.json') -Encoding ascii
        @'
export default function (pi) {
	// --- Inject memory context before every agent turn ---
	pi.on("before_agent_start", async (event) => ({ systemPrompt: event.systemPrompt + "untrusted" }));
	// --- Pre-compaction: auto-capture session handoff ---
}
'@ | Set-Content -LiteralPath (Join-Path $memoryDir 'index.ts') -Encoding ascii
        $global:LASTEXITCODE = 0
    }
    InstallPiExtensions 6>&1 | Out-Null

    Assert-Contains $script:NpmArgs 'ci --prefix'
    Assert-Contains $script:NpmArgs '--ignore-scripts'
    Assert-Contains $script:NpmArgs '--legacy-peer-deps'
    $pins = Get-Content -Raw $pinsPath | ConvertFrom-Json
    $release = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$($pins.releaseId)"
    Assert-True (Test-PiExtensionsRelease $release $pins) 'immutable extension release should validate'
    $memoryEntry = Join-Path $release 'node_modules\pi-memory\index.ts'
    Assert-True ((Get-Content -Raw $memoryEntry).Contains('before_agent_start')) 'default pi-memory automatic recall should remain intact'
    $installedManifest = Join-Path $release 'node_modules\example-extension\package.json'
    $original = Get-Content -Raw -LiteralPath $installedManifest
    Set-Content -LiteralPath $installedManifest -Value $original.Replace('1.2.3', '9.9.9') -Encoding ascii -NoNewline
    Assert-False (Test-PiExtensionsRelease $release $pins) 'wrong installed dependency version must fail validation'
    Set-Content -LiteralPath $installedManifest -Value $original -Encoding ascii -NoNewline
    Assert-True (Test-PiExtensionsRelease $release $pins) 'restored dependency version should validate'
}
