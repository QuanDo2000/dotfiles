# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
    $script:OriginalAddToUserPath = (Get-Command AddToUserPath).ScriptBlock
    $script:OriginalTestPiSourceHash = (Get-Command Test-PiSourceHash).ScriptBlock
    $script:OriginalGetFileSha256 = (Get-Command Get-FileSha256).ScriptBlock
    $windowsTarExpander = Get-Command Expand-WindowsTarArchive -ErrorAction SilentlyContinue
    $script:OriginalExpandWindowsTarArchive = if ($windowsTarExpander) { $windowsTarExpander.ScriptBlock } else { $null }
    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    $script:PythonCommand = if ($pythonLauncher) { $pythonLauncher.Source } else { (Get-Command python3 -ErrorAction Stop).Source }
    $script:PythonArguments = if ($pythonLauncher) { @('-3.14') } else { @() }
    Set-CommandMock 'RepairPiCompactionSteering' {}
}

function TestTeardown {
    foreach ($command in 'npm', 'npx', 'pi', 'py', 'Get-Command', 'Get-FileHash', 'Get-Process', 'New-Item', 'Copy-Item', 'Expand-Archive', 'Move-Item', 'Start-Process', 'Stop-Process', 'Wait-Process', 'irm', 'Invoke-RestMethod', 'Invoke-WebRequest', 'tar', 'bash-language-server', 'shellcheck', 'RepairPiCompactionSteering') {
        Clear-CommandMock $command
    }
    Set-FunctionMock 'AddToUserPath' $script:OriginalAddToUserPath
    Set-FunctionMock 'Test-PiSourceHash' $script:OriginalTestPiSourceHash
    Set-FunctionMock 'Get-FileSha256' $script:OriginalGetFileSha256
    if ($script:OriginalExpandWindowsTarArchive) { Set-FunctionMock 'Expand-WindowsTarArchive' $script:OriginalExpandWindowsTarArchive }
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

function Assert-AiInstructionCopyFailurePreservesTarget($Target) {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
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
    if (Try-Skip-If-No-Symlink-Privilege) { return }
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

function test_install_directory_rejects_reparse_point_parent {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $source = Join-Path $script:_TestTmp.FullName 'source-extension'
    $external = Join-Path $script:_TestTmp.FullName 'external-parent'
    $linkedParent = Join-Path $script:_TestTmp.FullName 'linked-parent'
    New-Item -ItemType Directory -Force -Path $source, $external | Out-Null
    'runtime' | Set-Content (Join-Path $source 'index.ts')
    New-Item -ItemType SymbolicLink -Path $linkedParent -Target $external | Out-Null

    Assert-Throws {
        Install-DirectoryWithRollback $source (Join-Path $linkedParent 'autoresearch') @('index.ts') 'Pi autoresearch extension'
    } 'reparse-point destination parent should fail closed'
    Assert-Equals 0 @(Get-ChildItem -LiteralPath $external -Force).Count
}

function test_install_directory_preserves_concurrent_destination_and_backup {
    $source = Join-Path $script:_TestTmp.FullName 'source-extension'
    $target = Join-Path $script:_TestTmp.FullName 'autoresearch'
    New-Item -ItemType Directory -Force -Path $source, $target | Out-Null
    'new' | Set-Content (Join-Path $source 'index.ts')
    'old' | Set-Content (Join-Path $target 'index.ts')
    Set-CommandMock 'Move-Item' {
        param($LiteralPath, $Destination, [switch]$Force, $ErrorAction)
        $concurrentTarget = [string]$LiteralPath
        if ($null -eq $ErrorAction) {
            Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
        } else {
            Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -ErrorAction $ErrorAction
        }
        New-Item -ItemType Directory -Force -Path $concurrentTarget | Out-Null
        'concurrent' | Set-Content (Join-Path $concurrentTarget 'concurrent.txt')
    }

    Assert-Throws {
        Install-DirectoryWithRollback $source $target @('index.ts') 'Pi autoresearch extension'
    } 'concurrent destination recreation should fail closed'
    if (-not (Test-Path -LiteralPath (Join-Path $target 'concurrent.txt'))) {
        throw 'concurrent destination missing'
    }
    Assert-Contains (Get-Content -Raw (Join-Path $target 'concurrent.txt')) 'concurrent'
    $backups = @(Get-ChildItem -LiteralPath (Split-Path $target -Parent) -Filter '.autoresearch.backup.*' -Directory -Force)
    Assert-Equals 1 $backups.Count
    if ($backups.Count -eq 1) { Assert-Contains (Get-Content -Raw (Join-Path $backups[0].FullName 'index.ts')) 'old' }
}

function test_installai_skills_copies_only_vendored_shared_skills {
    $script:DotfilesDir = Join-Path $script:_TestTmp.FullName 'dotfiles'
    $sourceRoot = Join-Path $script:DotfilesDir 'config\shared\ai\skills'
    $targetRoot = Join-Path $env:USERPROFILE '.agents\skills'
    $skills = @('systematic-debugging', 'tdd', 'skill-retrospective', 'reflect', 'unslop', 'blast-radius', 'github-code-review', 'github-pr-workflow', 'dotfiles-health-checks', 'agent-tool-benchmarking')
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
    New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot 'test-driven-development') | Out-Null
    'legacy' | Set-Content (Join-Path $targetRoot 'test-driven-development\SKILL.md')
    $oldPi = Join-Path $env:USERPROFILE '.pi\agent\skills\test-driven-development'
    New-Item -ItemType Directory -Force -Path $oldPi | Out-Null
    'old pi copy' | Set-Content (Join-Path $oldPi 'SKILL.md')
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
    Assert-False (Test-Path (Join-Path $targetRoot 'test-driven-development')) 'Old shared skill name remains discoverable'
    $retired = @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.agents') -Directory -Filter 'test-driven-development.backup.*')
    Assert-Equals 1 $retired.Count
    if ($retired.Count -eq 1) { Assert-Contains (Get-Content -Raw (Join-Path $retired[0].FullName 'SKILL.md')) 'legacy' }
    Assert-False (Test-Path (Join-Path $env:USERPROFILE '.pi\agent\skills\test-driven-development')) 'Old Pi skill remains discoverable'
    $piRetired = @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.pi\agent\retired-skills') -Directory -Filter 'test-driven-development.backup.*')
    Assert-Equals 1 $piRetired.Count
    if ($piRetired.Count -eq 1) { Assert-Contains (Get-Content -Raw (Join-Path $piRetired[0].FullName 'SKILL.md')) 'old pi copy' }
}

function test_ai_installers_do_not_expose_unused_update_switches {
    foreach ($name in 'InstallPiLanguageServers') {
        Assert-False ((Get-Command $name).Parameters.ContainsKey('Update')) "$name should not expose an unused update switch"
    }
}

function test_installpilanguageservers_installs_pinned_npm_servers {
    $script:LspInstalled = $false
    $script:NpmCalls = @()
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
    Assert-Contains $install 'bash-language-server@5.6.0'
}

function test_installpilanguageservers_skips_current_pinned_servers {
    $script:NpmCalls = @()
    Set-CommandMock 'bash-language-server' { '5.6.0'; $global:LASTEXITCODE = 0 }
    Set-CommandMock 'shellcheck' { $global:LASTEXITCODE = 0 }
    Set-CommandMock 'npm' { $script:NpmCalls += ,($args -join ' '); $global:LASTEXITCODE = 0 }

    InstallPiLanguageServers

    Assert-Equals 0 $script:NpmCalls.Count 'current pinned language servers should not be reinstalled'
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
        New-Item -ItemType Directory -Force -Path (Join-Path $package 'dist\core'), (Join-Path $package 'dist\bundle') | Out-Null
        Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $package 'npm-shrinkwrap.json')
        "{`"version`":`"$version`",`"devDependencies`":{`"typescript`":`"1.0.0`"}}" | Set-Content (Join-Path $package 'package.json')
        'entry' | Set-Content (Join-Path $package 'dist\bundle\cli.js')
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
    Assert-Contains (Get-Content -Raw -LiteralPath $launcher) 'dist\bundle\cli.js'
    Assert-Equals (Split-Path $launcher -Parent) (($env:Path -split ';')[0])
}

function test_installpi_verifies_cached_release_and_rejects_tamper {
    $version = Get-PinnedPiVersion
    $root = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    $releaseId = -join ((Get-PiSourceDigest (Get-PinnedPiSourceHash)) | ForEach-Object { $_.ToString('x2') })
    $release = Join-Path $root "releases\$version-$($releaseId.Substring(0, 12))-digest2"
    New-Item -ItemType Directory -Force -Path (Join-Path $release 'dist\core'), (Join-Path $release 'dist\bundle') | Out-Null
    Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $release 'npm-shrinkwrap.json')
    "{`"version`":`"$version`"}" | Set-Content (Join-Path $release 'package.json')
    'entry' | Set-Content (Join-Path $release 'dist\bundle\cli.js')
    Write-TestPatchedPiSession (Join-Path $release 'dist\core\agent-session.js')
    (Get-PiReleaseDigest $release) | Set-Content (Join-Path $release '.release.sha256') -NoNewline
    InstallPi
    'tampered' | Set-Content (Join-Path $release 'dist\bundle\cli.js')
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

function test_getfilesha256_runs_without_getfilehash_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { Skip-Test 'Windows PowerShell unavailable'; return }
    $fixture = Join-Path $script:_TestTmp.FullName 'hash-fixture'
    [IO.File]::WriteAllText($fixture, 'hash', [Text.Encoding]::ASCII)
    $expected = Get-TestSha256 'hash'
    $escapedScript = $script:DotfileScript.Replace("'", "''")
    $escapedFixture = $fixture.Replace("'", "''")
    $probe = ". '$escapedScript' -NoMain; `$env:PATH = `$env:SystemRoot + '\System32'; if ((Get-FileSha256 '$escapedFixture') -ne '$expected') { exit 1 }; 'hash-ok'"

    $output = & $windowsPowerShell.Source -NoProfile -NonInteractive -Command $probe 2>&1 | Out-String

    Assert-Contains $output 'hash-ok'
}

function test_pireleasedigest_matches_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { Skip-Test 'Windows PowerShell unavailable'; return }
    $fixture = Join-Path $script:_TestTmp.FullName 'pi-digest-fixture'
    New-Item -ItemType Directory -Force -Path $fixture | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'a-b'), 'hyphen', [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $fixture 'ab'), 'plain', [Text.Encoding]::ASCII)
    $expected = Get-PiReleaseDigest $fixture
    $escapedScript = $script:DotfileScript.Replace("'", "''")
    $escapedFixture = $fixture.Replace("'", "''")
    $probe = ". '$escapedScript' -NoMain; Get-PiReleaseDigest '$escapedFixture'"

    $actual = (& $windowsPowerShell.Source -NoProfile -NonInteractive -Command $probe | Select-Object -Last 1).Trim()

    Assert-Equals $expected $actual 'Pi release digest must not depend on the PowerShell runtime'
}

function test_comparepipackagelocks_runs_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { Skip-Test 'Windows PowerShell unavailable'; return }
    $escapedScript = $script:DotfileScript.Replace("'", "''")
    $lock = (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json').Replace("'", "''")
    $working = $script:_TestTmp.FullName.Replace("'", "''")
    $probe = ". '$escapedScript' -NoMain; Compare-PiPackageLocks '$lock' '$lock' '$working'"

    & $windowsPowerShell.Source -NoProfile -NonInteractive -Command $probe

    Assert-Equals 0 $LASTEXITCODE
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

function test_reportpiupdatestatus_explains_unpublished_latest_release {
    Set-CommandMock 'Invoke-RestMethod' { [pscustomobject]@{ version = '9.9.9' } }

    $output = Report-PiUpdateStatus '1.2.3' 6>&1 | Out-String

    Assert-Contains $output 'Pi 9.9.9 is available but the latest reviewed pin is 1.2.3'
    Assert-Contains $output 'Windows installs only published reviewed pins'
}

function test_installpi_source_checksum_fails_before_install {
    Set-CommandMock 'Invoke-WebRequest' { param($Uri, $OutFile) [IO.File]::WriteAllText($OutFile, 'bad') }
    Set-FunctionMock 'Test-PiSourceHash' { $false }
    Set-CommandMock 'npm' { throw 'npm must not run after checksum mismatch' }
    Assert-Throws { InstallPi } 'checksum mismatch must fail before npm'
}

function test_pi_release_validation_requires_version_and_entry {
    $dir = Join-Path $script:_TestTmp.FullName 'pi-release'
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'dist\core'), (Join-Path $dir 'dist\bundle') | Out-Null
    $version = Get-PinnedPiVersion
    $lock = Get-Content -Raw (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json')
    Copy-Item (Join-Path $script:RepoDir 'packages\pi-agent-npm-shrinkwrap.json') (Join-Path $dir 'npm-shrinkwrap.json')
    "{`"version`":`"$version`",`"dependencies`":{`"example-package`":`"1.0.0`"}}" | Set-Content (Join-Path $dir 'package.json')
    'entry' | Set-Content (Join-Path $dir 'dist\bundle\cli.js')
    Write-TestPatchedPiSession (Join-Path $dir 'dist\core\agent-session.js')
    (Get-PiReleaseDigest $dir) | Set-Content (Join-Path $dir '.release.sha256') -NoNewline
    Assert-False (Test-PiRelease $dir $version $lock) 'release missing dependency closure must fail'
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'node_modules\example-package') | Out-Null
    '{}' | Set-Content (Join-Path $dir 'node_modules\example-package\package.json')
    (Get-PiReleaseDigest $dir) | Set-Content (Join-Path $dir '.release.sha256') -NoNewline
    Assert-True (Test-PiRelease $dir $version $lock)
}

function Initialize-TestAutoresearchSource($SeedDir) {
    $source = Join-Path $SeedDir 'autoresearch'
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'skill') | Out-Null
    'export default function () {}' | Set-Content (Join-Path $source 'index.ts')
    'runtime' | Set-Content (Join-Path $source 'runtime.ts')
    'safety' | Set-Content (Join-Path $source 'safety.ts')
    'git' | Set-Content (Join-Path $source 'git.ts')
    'jj' | Set-Content (Join-Path $source 'jj.ts')
    'vcs' | Set-Content (Join-Path $source 'vcs.ts')
    'metrics' | Set-Content (Join-Path $source 'metrics.ts')
    "---`nname: pi-autoresearch`n---" | Set-Content (Join-Path $source 'skill\SKILL.md')
}

function Initialize-TestFastModeSource($SeedDir) {
    $source = Join-Path $SeedDir 'fast-mode'
    New-Item -ItemType Directory -Force -Path $source | Out-Null
    'export default function () {}' | Set-Content (Join-Path $source 'index.ts')
    'export function isFastModeModel() { return true }' | Set-Content (Join-Path $source 'core.ts')
}

function Initialize-TestReviewSource($SeedDir) {
    Copy-Item -LiteralPath (Join-Path $script:RepoDir 'config/shared/ai/pi/review') -Destination $SeedDir -Recurse
}

function Initialize-TestPiConfigSeeds {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $mergeDir = Join-Path $script:DotfilesDir 'scripts\seed_merge'
    New-Item -ItemType Directory -Force -Path $seedDir, $mergeDir | Out-Null
    Copy-Item (Join-Path $script:RepoDir 'scripts\seed_merge\*') $mergeDir
    '{}' | Set-Content -LiteralPath (Join-Path $seedDir 'mcp.json')
    foreach ($name in 'settings.json', 'keybindings.json', 'web-search.json') {
        '{}' | Set-Content -LiteralPath (Join-Path $seedDir $name)
    }
    'extension' | Set-Content -LiteralPath (Join-Path $seedDir 'codex-status.js')
    Initialize-TestAutoresearchSource $seedDir
    Initialize-TestFastModeSource $seedDir
    Initialize-TestReviewSource $seedDir

    return [pscustomobject]@{
        Source = Join-Path $seedDir 'codex-status.js'
        Target = Join-Path $env:USERPROFILE '.pi\agent\extensions\codex-status.js'
    }
}

function test_syncpiconfigs_restores_direct_copy_when_staged_replacement_fails {
    Initialize-TestPiConfigSeeds | Out-Null
    $destination = Join-Path $env:USERPROFILE '.pi\agent\extensions\codex-status.js'
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    'old extension' | Set-Content -LiteralPath $destination
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
    Assert-Equals 'old extension' ((Get-Content -Raw -LiteralPath $destination).Trim())
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $destination -Parent) -Filter 'codex-status.js.tmp.*' -Force).Count
    Assert-Equals 0 @(Get-ChildItem -LiteralPath (Split-Path $destination -Parent) -Filter 'codex-status.js.backup.*' -Force).Count
}

function test_syncpiconfigs_rejects_directory_direct_copy_destination {
    Initialize-TestPiConfigSeeds | Out-Null
    $destination = Join-Path $env:USERPROFILE '.pi\agent\extensions\codex-status.js'
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
    Assert-False (Test-Path -LiteralPath (Join-Path $destination 'codex-status.js')) 'source should not be copied inside destination directory'
}

function test_syncpiconfigs_creates_writable_seed_files {
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    New-Item -ItemType Directory -Force -Path $seedDir | Out-Null
    '{"theme":"dark"}' | Set-Content (Join-Path $seedDir 'settings.json')
    '{"app.model.cycleForward":[],"app.model.cycleBackward":[]}' | Set-Content (Join-Path $seedDir 'keybindings.json')
    '{"workflow":"none"}' | Set-Content (Join-Path $seedDir 'web-search.json')
    '{"mcpServers":{"unixOnly":{"command":"unix"}}}' | Set-Content (Join-Path $seedDir 'mcp.json')
    'extension' | Set-Content (Join-Path $seedDir 'codex-status.js')
    Initialize-TestAutoresearchSource $seedDir
    Initialize-TestFastModeSource $seedDir
    Initialize-TestReviewSource $seedDir
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    $staleAutoresearch = Join-Path $extensionDir 'autoresearch'
    $staleFastMode = Join-Path $extensionDir 'fast-mode'
    $baseDir = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    New-Item -ItemType Directory -Force -Path $staleAutoresearch, $staleFastMode, $baseDir | Out-Null
    'obsolete' | Set-Content (Join-Path $staleAutoresearch 'obsolete.ts')
    'obsolete' | Set-Content (Join-Path $staleFastMode 'obsolete.ts')
    $staleReview = Join-Path $extensionDir 'review'
    New-Item -ItemType Directory -Force -Path $staleReview | Out-Null
    'obsolete' | Set-Content (Join-Path $staleReview 'obsolete.ts')

    SyncPiConfigs

    $settings = Join-Path $env:USERPROFILE '.pi\agent\settings.json'
    $keybindings = Join-Path $env:USERPROFILE '.pi\agent\keybindings.json'
    $webSearch = Join-Path $env:USERPROFILE '.pi\web-search.json'
    $mcp = Join-Path $env:USERPROFILE '.pi\agent\mcp.json'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    Assert-FileExists $settings
    Assert-FileExists $keybindings
    Assert-FileExists $webSearch
    Assert-FileExists $mcp
    Assert-FileExists (Join-Path $baseDir 'settings.json')
    Assert-FileExists (Join-Path $baseDir 'keybindings.json')
    Assert-FileExists (Join-Path $baseDir 'web-search.json')
    Assert-FileExists (Join-Path $baseDir 'mcp.json')
    $keys = Get-Content -Raw $keybindings | ConvertFrom-Json
    Assert-Equals 0 @($keys.'app.model.cycleForward').Count
    Assert-Equals 0 @($keys.'app.model.cycleBackward').Count
    Assert-Equals 'none' (Get-Content -Raw $webSearch | ConvertFrom-Json).workflow
    Assert-Contains (Get-Content -Raw $mcp) '"unixOnly"'
    Assert-False ((Get-Content -Raw $mcp) -like '*windowsOnly*') 'Windows should deploy the shared MCP seed'
    Assert-FileExists (Join-Path $extensionDir 'codex-status.js')
    $autoresearch = Join-Path $extensionDir 'autoresearch'
    Assert-FileExists (Join-Path $autoresearch 'index.ts')
    Assert-FileExists (Join-Path $autoresearch 'runtime.ts')
    Assert-FileExists (Join-Path $autoresearch 'jj.ts')
    Assert-FileExists (Join-Path $autoresearch 'vcs.ts')
    Assert-FileExists (Join-Path $autoresearch 'skill\SKILL.md')
    Assert-False (Test-Path -LiteralPath (Join-Path $autoresearch 'obsolete.ts')) 'Pi autoresearch deployment should remove stale files'
    Assert-False ([bool]((Get-Item $autoresearch -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Pi autoresearch should be a real directory'
    $fastMode = Join-Path $extensionDir 'fast-mode'
    Assert-FileExists (Join-Path $fastMode 'index.ts')
    Assert-FileExists (Join-Path $fastMode 'core.ts')
    Assert-False (Test-Path -LiteralPath (Join-Path $fastMode 'obsolete.ts')) 'Pi fast-mode deployment should remove stale files'
    Assert-False ([bool]((Get-Item $fastMode -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Pi fast mode should be a real directory'
    $review = Join-Path $extensionDir 'review'
    foreach ($name in 'index.ts', 'target.ts', 'session.ts', 'rubric.md', 'LICENSE', 'UPSTREAM.md') {
        Assert-FileExists (Join-Path $review $name)
    }
    Assert-False (Test-Path -LiteralPath (Join-Path $review 'obsolete.ts')) 'review deployment should remove stale files'
    Assert-False ([bool]((Get-Item $review -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'review should be a real directory'
    Assert-False ([bool](Get-Item $settings).LinkType) 'Pi settings should stay writable'
}

function test_syncpiconfigs_rejects_overlapping_sync {
    $paths = Initialize-TestPiConfigSeeds
    New-Item -ItemType Directory -Force -Path (Split-Path $paths.Target -Parent) | Out-Null
    '{"globalConcurrencyLimit":99}' | Set-Content -LiteralPath $paths.Target
    $script:NestedPiConfigSyncAttempted = $false
    $script:NestedPiConfigSyncFailure = $null
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force, [switch]$Recurse, $ErrorAction)
        if (-not $script:NestedPiConfigSyncAttempted -and $LiteralPath -eq $paths.Source -and $Destination -like '*.tmp.*') {
            $script:NestedPiConfigSyncAttempted = $true
            try {
                SyncPiConfigs
            } catch {
                $script:NestedPiConfigSyncFailure = $_.Exception.Message
            }
        }
        if ($null -eq $ErrorAction) {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -Recurse:$Recurse
        } else {
            Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -Recurse:$Recurse -ErrorAction $ErrorAction
        }
    }

    SyncPiConfigs

    $lockPath = Join-Path $env:LOCALAPPDATA 'dotfiles\pi\sync.lock'
    Assert-True $script:NestedPiConfigSyncAttempted 'nested sync should be attempted'
    Assert-Contains $script:NestedPiConfigSyncFailure 'Pi config sync lock unavailable'
    Assert-Contains $script:NestedPiConfigSyncFailure $lockPath
}

function test_syncpiconfigs_skips_only_unchanged_regular_direct_copies {
    if (Try-Skip-If-No-Symlink-Privilege) { return }
    $script:DotfilesDir = Join-Path $env:USERPROFILE 'dotfiles'
    $seedDir = Join-Path $script:DotfilesDir 'config\shared\ai\pi'
    $extensionDir = Join-Path $env:USERPROFILE '.pi\agent\extensions'
    New-Item -ItemType Directory -Force -Path $seedDir, $extensionDir | Out-Null
    '{}' | Set-Content -LiteralPath (Join-Path $seedDir 'mcp.json')

    foreach ($name in 'settings.json', 'keybindings.json', 'web-search.json') {
        '{}' | Set-Content -LiteralPath (Join-Path $seedDir $name)
    }
    'linked replacement' | Set-Content -LiteralPath (Join-Path $seedDir 'codex-status.js')
    Initialize-TestAutoresearchSource $seedDir
    Initialize-TestFastModeSource $seedDir
    Initialize-TestReviewSource $seedDir
    $external = Join-Path $script:_TestTmp.FullName 'external-codex-status.js'
    'external' | Set-Content -LiteralPath $external
    New-Item -ItemType SymbolicLink -Path (Join-Path $extensionDir 'codex-status.js') -Target $external | Out-Null

    $script:PiConfigCopies = @()
    Set-CommandMock 'Copy-Item' {
        param($LiteralPath, $Destination, [switch]$Force, [switch]$Recurse)
        $script:PiConfigCopies += $Destination
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force -Recurse:$Recurse
    }

    SyncPiConfigs

    $linkedExtension = Join-Path $extensionDir 'codex-status.js'
    Assert-Equals 1 @($script:PiConfigCopies | Where-Object { $_ -like "$linkedExtension.tmp.*" }).Count
    Assert-False ([bool](Get-Item -LiteralPath $linkedExtension -Force).LinkType) 'linked extension should become a regular file'
    Assert-Equals 'linked replacement' ((Get-Content -Raw -LiteralPath $linkedExtension).Trim())
    Assert-Equals 'external' ((Get-Content -Raw -LiteralPath $external).Trim())
}
