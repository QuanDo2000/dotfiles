# Windows font and Node.js installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_installfont_fails_when_scoop_install_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'scoop') { return [pscustomobject]@{ Source = 'mock-scoop' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'scoop' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallFont 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'scoop'
        Clear-CommandMock 'Get-Command'
    }

    Assert-True $failed 'InstallFont should fail when scoop install fails'
}

function test_installfont_skips_existing_nerd_fonts_bucket {
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
            'main'
            'nerd-fonts'
        }
        $global:LASTEXITCODE = 0
    }

    try {
        InstallFont 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'scoop'
        Clear-CommandMock 'Get-Command'
    }

    Assert-False ($script:ScoopCalls -contains 'bucket add nerd-fonts') 'existing nerd-fonts bucket should not be added again'
    Assert-True ($script:ScoopCalls -contains 'install FiraCode') 'font install should still run'
}

function test_installfnm_fails_when_fnm_command_fails {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'fnm') { return [pscustomobject]@{ Source = 'mock-fnm' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'fnm' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallFnm 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'fnm'
        Clear-CommandMock 'Get-Command'
    }

    Assert-True $failed 'InstallFnm should fail when fnm install/use/default fails'
}
