# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    foreach ($command in 'Get-Command', 'scoop', 'fnm') { Clear-CommandMock $command }
    Clear-TestEnv
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
