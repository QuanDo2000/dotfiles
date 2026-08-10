# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'Invoke-WebRequest', 'Set-ExecutionPolicy', 'scoop', 'fnm') { Clear-CommandMock $command }
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

function test_installscooppackages_skips_existing_nerd_fonts_bucket {
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
            [pscustomobject]@{ Name = 'nerd-fonts' }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages 6>&1 | Out-Null

    Assert-False ($script:ScoopCalls -contains 'bucket add nerd-fonts') 'existing nerd-fonts bucket should not be added again'
    Assert-True ($script:ScoopCalls -contains 'install FiraCode') 'FiraCode install should still run'
    Assert-True ($script:ScoopCalls -contains 'install jq') 'jq should be managed by Scoop'
    Assert-True ($script:ScoopCalls -contains 'install ast-grep') 'ast-grep should be managed by Scoop'
}

function test_installscooppackages_updates_only_managed_packages {
    $script:Dry = $false
    $script:ScoopCalls = @()
    Set-CommandMock 'Get-Command' { [pscustomobject]@{ Source = 'mock-scoop' } }
    Set-CommandMock 'scoop' {
        $script:ScoopCalls += ,($args -join ' ')
        if ($args[0] -eq 'bucket' -and $args[1] -eq 'list') {
            [pscustomobject]@{ Name = 'nerd-fonts' }
        }
        if ($args[0] -eq 'list') {
            Get-ScoopPackages | ForEach-Object { [pscustomobject]@{ Name = $_ } }
        }
        $global:LASTEXITCODE = 0
    }

    InstallScoopPackages -Update 6>&1 | Out-Null

    Assert-True ($script:ScoopCalls -contains 'update') 'Scoop manifests should update'
    Assert-True ($script:ScoopCalls -contains 'update FiraCode jq ast-grep') 'only managed Scoop packages should update'
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
