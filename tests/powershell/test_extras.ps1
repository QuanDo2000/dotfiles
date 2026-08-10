# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
    $script:DotfilesDir = $script:RepoDir
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'Get-ItemProperty', 'Invoke-WebRequest', 'New-ItemProperty', 'Remove-ItemProperty', 'Set-ExecutionPolicy', 'scoop', 'fnm') { Clear-CommandMock $command }
    Remove-Variable ScoopBootstrapCalls, ScoopBootstrapExecuted -Scope Global -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function Write-TestScoopBootstrap($Path, $Body) {
    $source = @'
param([switch]$RunAsAdmin)
function Test-CommandAvailable { return $true }
$SCOOP_PACKAGE_REPO = 'https://github.com/ScoopInstaller/Scoop/archive/master.zip'
$SCOOP_MAIN_BUCKET_REPO = 'https://github.com/ScoopInstaller/Main/archive/master.zip'
$downloadPath = 'zip'
if (Test-CommandAvailable('git')) { $downloadPath = 'git' }
__BODY__
'@
    [IO.File]::WriteAllText($Path, $source.Replace('__BODY__', $Body), [Text.UTF8Encoding]::new($false))
}

function test_installscoop_executes_only_verified_pinned_script {
    $global:ScoopBootstrapCalls = @()
    $global:ScoopBootstrapExecuted = $false
    $script:DownloadedFiles = @()
    $script:RequestedInstallerUri = $null
    $originalHashes = @($script:ScoopInstallerSha256, $script:ScoopCoreSha256, $script:ScoopMainSha256)
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'scoop') {
            if ($global:ScoopBootstrapExecuted) { return [pscustomobject]@{ Source = 'mock-scoop' } }
            return $null
        }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $script:DownloadedFiles += $OutFile
        switch -Wildcard ([string]$Uri) {
            '*ScoopInstaller/Install/*' {
                $script:RequestedInstallerUri = [string]$Uri
                $global:ScoopBootstrapCalls += 'download:installer'
                Write-TestScoopBootstrap $OutFile '$global:ScoopBootstrapCalls += "execute:$([bool]$RunAsAdmin):${downloadPath}:${SCOOP_PACKAGE_REPO}:${SCOOP_MAIN_BUCKET_REPO}"; $global:ScoopBootstrapExecuted = $true'
                $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            '*ScoopInstaller/Scoop/archive/*' {
                $global:ScoopBootstrapCalls += 'download:core'
                [IO.File]::WriteAllText($OutFile, 'core', [Text.UTF8Encoding]::new($false))
                $script:ScoopCoreSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            '*ScoopInstaller/Main/archive/*' {
                $global:ScoopBootstrapCalls += 'download:main'
                [IO.File]::WriteAllText($OutFile, 'main', [Text.UTF8Encoding]::new($false))
                $script:ScoopMainSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    Set-CommandMock 'Set-ExecutionPolicy' { $global:ScoopBootstrapCalls += 'policy' }

    try {
        InstallScoop
    } finally {
        $script:ScoopInstallerSha256, $script:ScoopCoreSha256, $script:ScoopMainSha256 = $originalHashes
    }

    Assert-Equals 'download:installer download:core download:main policy' (($global:ScoopBootstrapCalls | Select-Object -First 4) -join ' ')
    $calls = $global:ScoopBootstrapCalls -join ' '
    Assert-Contains $calls 'execute:True:zip:file:'
    Assert-False ($calls -like '*master.zip*') 'Executed Scoop bootstrap should use only local pinned archives'
    Assert-Equals "https://raw.githubusercontent.com/ScoopInstaller/Install/$script:ScoopInstallerCommit/install.ps1" $script:RequestedInstallerUri
    foreach ($path in $script:DownloadedFiles) {
        Assert-False (Test-Path -LiteralPath $path) 'Scoop bootstrap temp files should be removed'
    }
}

function test_installscoop_rejects_core_archive_mismatch_before_execution {
    $global:ScoopBootstrapCalls = @()
    $script:DownloadedFiles = @()
    $originalHashes = @($script:ScoopInstallerSha256, $script:ScoopMainSha256)
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $script:DownloadedFiles += $OutFile
        switch -Wildcard ([string]$Uri) {
            '*ScoopInstaller/Install/*' {
                Write-TestScoopBootstrap $OutFile '$global:ScoopBootstrapCalls += "execute"'
                $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            '*ScoopInstaller/Scoop/archive/*' { [IO.File]::WriteAllText($OutFile, 'wrong core') }
            '*ScoopInstaller/Main/archive/*' {
                [IO.File]::WriteAllText($OutFile, 'main')
                $script:ScoopMainSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    Set-CommandMock 'Set-ExecutionPolicy' { $global:ScoopBootstrapCalls += 'policy' }

    try {
        Assert-Throws { InstallScoop } 'Scoop core checksum mismatch should fail'
    } finally {
        $script:ScoopInstallerSha256, $script:ScoopMainSha256 = $originalHashes
    }
    Assert-Equals '' ($global:ScoopBootstrapCalls -join ' ')
    foreach ($path in $script:DownloadedFiles) {
        Assert-False (Test-Path -LiteralPath $path) 'Rejected Scoop archives should be removed'
    }
}

function test_installscoop_rejects_checksum_mismatch_before_execution {
    $global:ScoopBootstrapCalls = @()
    $global:ScoopBootstrapExecuted = $false
    $script:DownloadedInstaller = $null
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $script:DownloadedInstaller = $OutFile
        $global:ScoopBootstrapCalls += 'download'
        [IO.File]::WriteAllText($OutFile, '$global:ScoopBootstrapExecuted = $true', [Text.UTF8Encoding]::new($false))
    }
    Set-CommandMock 'Set-ExecutionPolicy' { $global:ScoopBootstrapCalls += 'policy' }

    Assert-Throws { InstallScoop } 'Scoop checksum mismatch should fail'
    Assert-Equals 'download' ($global:ScoopBootstrapCalls -join ' ')
    Assert-False $global:ScoopBootstrapExecuted 'Mismatched Scoop installer should not execute'
    Assert-False (Test-Path -LiteralPath $script:DownloadedInstaller) 'Rejected Scoop installer should be removed'
}

function test_installscoop_fails_when_temp_cleanup_fails {
    $global:ScoopBootstrapExecuted = $false
    $script:DownloadedInstaller = $null
    $originalHash = $script:ScoopInstallerSha256
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $script:DownloadedInstaller = $OutFile
        [IO.File]::WriteAllText($OutFile, '$global:ScoopBootstrapExecuted = $true', [Text.UTF8Encoding]::new($false))
        $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Set-CommandMock 'Set-ExecutionPolicy' { }
    Set-CommandMock 'Remove-Item' {
        param($LiteralPath, $Path, [switch]$Force, $ErrorAction)
        if ([string]$ErrorAction -eq 'SilentlyContinue') { return }
        throw 'locked installer'
    }

    try {
        Assert-Throws { InstallScoop } 'Scoop cleanup failure should fail installation'
        Assert-False $global:ScoopBootstrapExecuted 'Scoop installer should not execute when cleanup fails'
    } finally {
        $script:ScoopInstallerSha256 = $originalHash
        Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item -Force -ErrorAction SilentlyContinue
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $script:DownloadedInstaller -Force -ErrorAction SilentlyContinue
    }
}

function test_installscoop_surfaces_in_memory_bootstrap_break_failure {
    $originalHashes = @($script:ScoopInstallerSha256, $script:ScoopCoreSha256, $script:ScoopMainSha256)
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        switch -Wildcard ([string]$Uri) {
            '*ScoopInstaller/Install/*' {
                Write-TestScoopBootstrap $OutFile '$global:LASTEXITCODE = 23; break'
                $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            '*ScoopInstaller/Scoop/archive/*' {
                [IO.File]::WriteAllText($OutFile, 'core', [Text.UTF8Encoding]::new($false))
                $script:ScoopCoreSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            '*ScoopInstaller/Main/archive/*' {
                [IO.File]::WriteAllText($OutFile, 'main', [Text.UTF8Encoding]::new($false))
                $script:ScoopMainSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    Set-CommandMock 'Set-ExecutionPolicy' { }

    try {
        Assert-Throws { InstallScoop } 'Failed in-memory Scoop bootstrap should reach command verification'
        Assert-Equals 23 $global:LASTEXITCODE
    } finally {
        $script:ScoopInstallerSha256, $script:ScoopCoreSha256, $script:ScoopMainSha256 = $originalHashes
        $global:LASTEXITCODE = 0
    }
}

function test_scoop_bootstrap_archive_patch_rejects_source_drift {
    Assert-Throws { Set-ScoopBootstrapArchives 'unexpected source' 'file:///core.zip' 'file:///main.zip' } 'Scoop source drift should fail closed'
}

function test_scoop_bootstrap_archive_patch_escapes_apostrophes {
    $source = @'
if (Test-CommandAvailable('git')) {
}
$SCOOP_PACKAGE_REPO = 'https://github.com/ScoopInstaller/Scoop/archive/master.zip'
$SCOOP_MAIN_BUCKET_REPO = 'https://github.com/ScoopInstaller/Main/archive/master.zip'
'@

    $patched = Set-ScoopBootstrapArchives $source "file:///C:/Users/O'Neil/core.zip" "file:///C:/Users/O'Neil/main.zip"
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseInput($patched, [ref]$tokens, [ref]$errors) | Out-Null

    Assert-Equals 0 $errors.Count
    Assert-Contains $patched "O''Neil/core.zip"
    Assert-Contains $patched "O''Neil/main.zip"
}

function test_scoop_locked_local_archive_works_in_windows_powershell {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) { return }

    $source = Join-Path $script:_TestTmp.FullName 'locked-source.zip'
    $destination = Join-Path $script:_TestTmp.FullName 'locked-copy.zip'
    [IO.File]::WriteAllText($source, 'locked archive', [Text.UTF8Encoding]::new($false))
    $oldSource = $env:SCOOP_TEST_SOURCE
    $oldDestination = $env:SCOOP_TEST_DESTINATION
    $env:SCOOP_TEST_SOURCE = $source
    $env:SCOOP_TEST_DESTINATION = $destination
    $probe = @'
$ErrorActionPreference = 'Stop'
$lock = [IO.File]::Open($env:SCOOP_TEST_SOURCE, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    $uri = [Uri]::new((Resolve-Path -LiteralPath $env:SCOOP_TEST_SOURCE).Path)
    (New-Object Net.WebClient).DownloadFile($uri, $env:SCOOP_TEST_DESTINATION)
} finally {
    $lock.Dispose()
}
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($env:SCOOP_TEST_SOURCE)) -ne
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($env:SCOOP_TEST_DESTINATION))) { exit 1 }
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))

    try {
        & $windowsPowerShell.Source -NoProfile -NonInteractive -EncodedCommand $encoded
        Assert-Equals 0 $LASTEXITCODE
    } finally {
        $env:SCOOP_TEST_SOURCE = $oldSource
        $env:SCOOP_TEST_DESTINATION = $oldDestination
    }
}

function test_scoop_bootstrap_pins_core_and_main_archives {
    Assert-Equals 'b588a06e41d920d2123ec70aee682bae14935939' $script:ScoopCoreCommit
    Assert-Equals '630206995f30866a0b25b00c14c74be9ef9b79c4911f72f6efd2625cfe19a645' $script:ScoopCoreSha256
    Assert-Equals '72a1eb40859d2a17614bf187570e4275c43e84a3' $script:ScoopMainCommit
    Assert-Equals '88eff1564c463157958bc817ac30d6111f2e7c01fec702e67fef5cad96a4bc07' $script:ScoopMainSha256
    $source = @'
if (Test-CommandAvailable('git')) {
}
$SCOOP_PACKAGE_REPO = 'https://github.com/ScoopInstaller/Scoop/archive/master.zip'
$SCOOP_MAIN_BUCKET_REPO = 'https://github.com/ScoopInstaller/Main/archive/master.zip'
'@

    $patched = Set-ScoopBootstrapArchives $source 'file:///core.zip' 'file:///main.zip'

    Assert-Contains $patched 'if ($false) {'
    Assert-Contains $patched "`$SCOOP_PACKAGE_REPO = 'file:///core.zip'"
    Assert-Contains $patched "`$SCOOP_MAIN_BUCKET_REPO = 'file:///main.zip'"
    Assert-False ($patched -like '*master.zip*') 'Patched bootstrap should not retain mutable archives'
}

function test_scoop_bootstrap_uses_immutable_reviewed_pin {
    Assert-Equals 'b0ee913725139b816f9178163af0aecdba07a7ed' $script:ScoopInstallerCommit
    Assert-Equals '48f6ea398b3a3fa26fae0093d37bd85b13e7eaa5d1d4a3e208408768408e35ae' $script:ScoopInstallerSha256
    $scriptText = Get-Content -Raw $script:DotfileScript
    Assert-Contains $scriptText 'raw.githubusercontent.com/ScoopInstaller/Install/$script:ScoopInstallerCommit/install.ps1'
    Assert-False ($scriptText -like '*get.scoop.sh*') 'Mutable Scoop bootstrap URL should be removed'
    Assert-False ($scriptText -like '*Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression*') 'Remote Scoop script should not be piped to execution'
    Assert-Contains $scriptText 'ReadAllBytes($installer)'
    Assert-Contains $scriptText 'Create($source)'
    Assert-Contains $scriptText 'do { & $bootstrap -RunAsAdmin } while ($false)'
    Assert-False ($scriptText -like '*& $installer -RunAsAdmin*') 'Verified bytes should execute from memory, not a reopenable temp path'
}

function test_font_manifest_installs_new_version_while_old_font_is_locked {
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { return }
    $manifest = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json') | ConvertFrom-Json
    $dir = Join-Path $script:_TestTmp.FullName 'font-source'
    $fontInstallDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $dir, $fontInstallDir | Out-Null
    $fontName = 'FiraCodeNerdFont-Bold.ttf'
    [IO.File]::WriteAllText((Join-Path $dir $fontName), 'new font')
    $oldFont = Join-Path $fontInstallDir $fontName
    [IO.File]::WriteAllText($oldFont, 'locked old font')
    $lock = [IO.File]::Open($oldFont, 'Open', 'Read', 'Read')
    $script:RegisteredFontValue = $null
    Set-CommandMock 'Get-ItemProperty' { [pscustomobject]@{ CurrentBuildNumber = 22631 } }
    Set-CommandMock 'New-ItemProperty' {
        param($Path, $Name, $Value, [switch]$Force)
        $script:RegisteredFontValue = $Value
    }
    $global = $false
    $version = $manifest.version

    try {
        & ([scriptblock]::Create(($manifest.installer.script -join "`n")))
    } finally {
        $lock.Dispose()
    }

    $versionedFont = Join-Path $fontInstallDir "FiraCodeNerdFont-Bold-$($manifest.version).ttf"
    Assert-True (Test-Path -LiteralPath $versionedFont) 'new font should use a versioned path instead of overwriting locked font'
    Assert-Equals $versionedFont $script:RegisteredFontValue
    Assert-Equals 'locked old font' ([IO.File]::ReadAllText($oldFont))

    $currentLock = [IO.File]::Open($versionedFont, 'Open', 'Read', 'Read')
    try {
        & ([scriptblock]::Create(($manifest.installer.script -join "`n")))
    } finally {
        $currentLock.Dispose()
    }
    Assert-Equals 'new font' ([IO.File]::ReadAllText($versionedFont))
}

function test_font_manifest_upgrades_while_installed_version_is_locked {
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { return }
    $manifest = Get-Content -Raw (Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json') | ConvertFrom-Json
    Assert-False ($manifest.PSObject.Properties.Name -contains 'pre_uninstall') 'locked old font must not block versioned upgrade'
    $dir = Join-Path $script:_TestTmp.FullName 'font-source'
    $fontInstallDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    New-Item -ItemType Directory -Force -Path $dir, $fontInstallDir | Out-Null
    $fontName = 'FiraCodeNerdFont-Bold.ttf'
    [IO.File]::WriteAllText((Join-Path $dir $fontName), 'new font')
    $oldFont = Join-Path $fontInstallDir 'FiraCodeNerdFont-Bold-previous.ttf'
    [IO.File]::WriteAllText($oldFont, 'locked old font')
    $lock = [IO.File]::Open($oldFont, 'Open', 'Read', 'Read')
    Set-CommandMock 'Get-ItemProperty' { [pscustomobject]@{ CurrentBuildNumber = 22631 } }
    Set-CommandMock 'New-ItemProperty' { }
    Set-CommandMock 'Remove-ItemProperty' { }
    $global = $false

    try {
        $version = 'previous'
        & ([scriptblock]::Create(($manifest.uninstaller.script -join "`n")))
        $version = $manifest.version
        & ([scriptblock]::Create(($manifest.installer.script -join "`n")))
    } finally {
        $lock.Dispose()
    }

    $newFont = Join-Path $fontInstallDir "FiraCodeNerdFont-Bold-$($manifest.version).ttf"
    Assert-True (Test-Path -LiteralPath $newFont) 'new version should install beside locked old version'
    Assert-Equals 'locked old font' ([IO.File]::ReadAllText($oldFont))
}

function test_installscooppackages_fails_when_scoop_install_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'scoop') { return [pscustomobject]@{ Source = 'mock-scoop' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'scoop' { $global:LASTEXITCODE = 1 }

    Assert-Throws { InstallScoopPackages 6>&1 | Out-Null } 'InstallScoopPackages should fail when scoop install fails'
}

function test_installscooppackages_replaces_mutable_font_bucket_with_local_manifest {
    $script:Dry = $false
    $script:ScoopCalls = @()
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'scoop') { return [pscustomobject]@{ Source = 'mock-scoop' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'bucket' -and $args[1] -eq 'list') {
            [pscustomobject]@{ Name = 'main' }
            [pscustomobject]@{ Name = 'nerd-fonts'; Source = 'https://github.com/matthewjberger/scoop-nerd-fonts' }
        }
        if ($args[0] -eq 'list') {
            [pscustomobject]@{ Name = 'FiraCode' }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    $fontManifest = Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json'
    Assert-True ($script:ScoopCalls -contains 'bucket rm nerd-fonts') 'legacy mutable font bucket should be removed'
    Assert-False ($script:ScoopCalls -contains 'bucket add nerd-fonts') 'mutable font bucket should not be added'
    Assert-True ($script:ScoopCalls -contains "install $fontManifest") 'tracked FiraCode Nerd Font manifest should be installed'
    Assert-True ($script:ScoopCalls -contains 'uninstall FiraCode') 'obsolete non-Nerd Font package should be removed'
    Assert-True ($script:ScoopCalls -contains 'install jq') 'jq should be managed by Scoop'
    Assert-True ($script:ScoopCalls -contains 'install ast-grep') 'ast-grep should be managed by Scoop'
}

function test_installscooppackages_reinstalls_bucket_managed_firacode_nf {
    $script:Dry = $false
    $script:ScoopCalls = @()
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'bucket' -and $args[1] -eq 'list') {
            [pscustomobject]@{ Name = 'nerd-fonts'; Source = 'https://github.com/matthewjberger/scoop-nerd-fonts' }
        }
        if ($args[0] -eq 'list') {
            [pscustomobject]@{ Name = 'FiraCode-NF'; Source = 'nerd-fonts' }
            [pscustomobject]@{ Name = 'jq'; Source = 'main' }
            [pscustomobject]@{ Name = 'ast-grep'; Source = 'main' }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    $fontManifest = Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json'
    Assert-True ($script:ScoopCalls -contains 'uninstall FiraCode-NF') 'bucket-managed font should be replaced'
    Assert-True ($script:ScoopCalls -contains "install $fontManifest") 'reviewed local font manifest should replace bucket package'
    Assert-True ([Array]::IndexOf($script:ScoopCalls, 'uninstall FiraCode-NF') -lt [Array]::IndexOf($script:ScoopCalls, 'bucket rm nerd-fonts')) 'bucket package should be removed before its bucket'
}

function test_installscooppackages_recovers_after_legacy_font_bucket_was_removed {
    $script:Dry = $false
    $script:ScoopCalls = @()
    $script:LegacyFontInstalled = $true
    $legacyFontDir = Join-Path $script:_TestTmp.FullName 'legacy-font'
    New-Item -ItemType Directory -Path $legacyFontDir | Out-Null
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'prefix') {
            if ($args[1] -eq 'FiraCode' -and $script:LegacyFontInstalled) {
                $legacyFontDir
                $global:LASTEXITCODE = 0
            } else {
                $global:LASTEXITCODE = 1
            }
            return
        }
        if ($args[0] -eq 'uninstall' -and $args[1] -eq 'FiraCode') {
            $script:LegacyFontInstalled = $false
        }
        if ($args[0] -eq 'list') {
            if ($script:LegacyFontInstalled) { throw "Cannot find path 'C:\Users\test\scoop\buckets\nerd-fonts\' because it does not exist." }
            [pscustomobject]@{ Name = 'jq'; Source = 'main' }
            [pscustomobject]@{ Name = 'ast-grep'; Source = 'main' }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    $fontManifest = Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json'
    Assert-True ($script:ScoopCalls -contains 'uninstall FiraCode') 'stale legacy font should be removed without its bucket'
    Assert-True ($script:ScoopCalls -contains "install $fontManifest") 'tracked local font should replace stale legacy font'
}

function test_installscooppackages_recovers_bucket_managed_font_after_bucket_was_removed {
    $script:Dry = $false
    $script:ScoopCalls = @()
    $script:BucketFontInstalled = $true
    $installedFontDir = Join-Path $script:_TestTmp.FullName 'bucket-font'
    New-Item -ItemType Directory -Path $installedFontDir | Out-Null
    '{"bucket":"nerd-fonts"}' | Set-Content -LiteralPath (Join-Path $installedFontDir 'install.json')
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'prefix') {
            if ($args[1] -eq 'FiraCode-NF' -and $script:BucketFontInstalled) {
                $installedFontDir
                $global:LASTEXITCODE = 0
            } else {
                $global:LASTEXITCODE = 1
            }
            return
        }
        if ($args[0] -eq 'uninstall' -and $args[1] -eq 'FiraCode-NF') {
            $script:BucketFontInstalled = $false
        }
        if ($args[0] -eq 'list') {
            if ($script:BucketFontInstalled) { throw "Cannot find path 'C:\Users\test\scoop\buckets\nerd-fonts\' because it does not exist." }
            [pscustomobject]@{ Name = 'jq'; Source = 'main' }
            [pscustomobject]@{ Name = 'ast-grep'; Source = 'main' }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    $fontManifest = Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json'
    Assert-True ($script:ScoopCalls -contains 'uninstall FiraCode-NF') 'stale bucket-managed font should be removed without its bucket'
    Assert-True ($script:ScoopCalls -contains "install $fontManifest") 'tracked local font should replace stale bucket-managed font'
}

function test_installscooppackages_rejects_unexpected_nerd_fonts_bucket {
    $script:Dry = $false
    $script:ScoopCalls = @()
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'bucket' -and $args[1] -eq 'list') {
            [pscustomobject]@{ Name = 'nerd-fonts'; Source = 'https://example.com/custom-fonts' }
        }
        $global:LASTEXITCODE = 0
    }

    Assert-Throws { InstallScoopPackages 6>&1 | Out-Null } 'unexpected bucket source should fail closed'
    Assert-False ($script:ScoopCalls -contains 'bucket rm nerd-fonts') 'custom bucket should not be deleted'
}

function test_installscooppackages_keeps_reviewed_scoop_snapshot_during_update {
    $script:Dry = $false
    $script:ScoopCalls = @()
    $fontManifest = Join-Path $script:DotfilesDir 'config\windows\scoop\FiraCode-NF.json'
    $installedFontDir = Join-Path $script:_TestTmp.FullName 'installed-font'
    New-Item -ItemType Directory -Path $installedFontDir | Out-Null
    Copy-Item -LiteralPath $fontManifest -Destination (Join-Path $installedFontDir 'manifest.json')
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'list') {
            [pscustomobject]@{ Name = 'FiraCode-NF'; Source = $fontManifest }
            [pscustomobject]@{ Name = 'jq'; Source = 'main' }
            [pscustomobject]@{ Name = 'ast-grep'; Source = 'main' }
        }
        if ($args[0] -eq 'prefix') { $installedFontDir }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    Assert-False ($script:ScoopCalls -contains 'update') 'Scoop code and manifests should require reviewed pin changes'
    Assert-False (($script:ScoopCalls -join "`n") -like 'update *') 'Scoop packages should remain on reviewed manifests'
}

function test_installfnm_uses_pi_extension_node_pin {
    $script:Dry = $false
    $script:FnmCalls = @()
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-fnm' } }
    Set-CommandMock 'fnm' {
        $script:FnmCalls += ,($args -join ' ')
        if ($args[0] -eq 'env') { '' }
        $global:LASTEXITCODE = 0
    }

    InstallFnm 6>&1 | Out-Null

    Assert-True ($script:FnmCalls -contains 'install 24.18.1') 'fnm should install locked Node version'
    Assert-True ($script:FnmCalls -contains 'use 24.18.1') 'fnm should use locked Node version'
    Assert-True ($script:FnmCalls -contains 'default 24.18.1') 'fnm should default to locked Node version'
    Assert-False (($script:FnmCalls -join "`n") -like '*lts-latest*') 'Node version should not float'
}

function test_installfnm_fails_when_fnm_command_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'fnm') { return [pscustomobject]@{ Source = 'mock-fnm' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'fnm' { $global:LASTEXITCODE = 1 }

    Assert-Throws { InstallFnm 6>&1 | Out-Null } 'InstallFnm should fail when fnm install/use/default fails'
}
