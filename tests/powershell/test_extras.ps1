# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'Invoke-WebRequest', 'Set-ExecutionPolicy', 'scoop', 'fnm') { Clear-CommandMock $command }
    Remove-Variable ScoopBootstrapCalls, ScoopBootstrapExecuted -Scope Global -ErrorAction SilentlyContinue
    Clear-TestEnv
}

function test_installscoop_executes_only_verified_pinned_script {
    $global:ScoopBootstrapCalls = @()
    $global:ScoopBootstrapExecuted = $false
    $script:DownloadedInstaller = $null
    $script:RequestedInstallerUri = $null
    $originalHash = $script:ScoopInstallerSha256
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
        $script:DownloadedInstaller = $OutFile
        $script:RequestedInstallerUri = [string]$Uri
        $global:ScoopBootstrapCalls += 'download'
        $source = @'
param([switch]$RunAsAdmin)
$global:ScoopBootstrapCalls += "execute:$([bool]$RunAsAdmin)"
$global:ScoopBootstrapExecuted = $true
'@
        [IO.File]::WriteAllText($OutFile, $source, [Text.UTF8Encoding]::new($false))
        $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Set-CommandMock 'Set-ExecutionPolicy' { $global:ScoopBootstrapCalls += 'policy' }

    try {
        InstallScoop
    } finally {
        $script:ScoopInstallerSha256 = $originalHash
    }

    Assert-Equals 'download policy execute:True' ($global:ScoopBootstrapCalls -join ' ')
    Assert-Equals "https://raw.githubusercontent.com/ScoopInstaller/Install/$script:ScoopInstallerCommit/install.ps1" $script:RequestedInstallerUri
    Assert-False (Test-Path -LiteralPath $script:DownloadedInstaller) 'Scoop installer temp file should be removed'
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
    $originalHash = $script:ScoopInstallerSha256
    Set-CommandMock 'Get-Command' { return $null }
    Set-CommandMock 'Invoke-WebRequest' {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $source = '$global:LASTEXITCODE = 23; break'
        [IO.File]::WriteAllText($OutFile, $source, [Text.UTF8Encoding]::new($false))
        $script:ScoopInstallerSha256 = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Set-CommandMock 'Set-ExecutionPolicy' { }

    try {
        Assert-Throws { InstallScoop } 'Failed in-memory Scoop bootstrap should reach command verification'
        Assert-Equals 23 $global:LASTEXITCODE
    } finally {
        $script:ScoopInstallerSha256 = $originalHash
        $global:LASTEXITCODE = 0
    }
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
