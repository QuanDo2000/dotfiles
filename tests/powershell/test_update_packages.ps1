# Tests for Windows update/package helpers in dotfile.ps1.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

# ---------------------------------------------------------------------------
# Update-Packages
# ---------------------------------------------------------------------------

function test_update_packages_dry_run_does_not_call_winget {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'winget' { $script:called = $true }

    try {
        $output = Update-Packages 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'winget'
    }

    Assert-Contains $output 'Would run: winget upgrade --all'
    Assert-False $called 'winget should not be invoked in dry run'
}

function test_update_packages_fails_when_winget_upgrade_fails {
    $script:Dry = $false
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    Set-Item -Path function:global:InstallAi -Value { }

    $failed = $false
    try {
        Update-Packages 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'winget'
        Set-Item -Path function:global:InstallAi -Value $originalInstallAi
    }

    Assert-True $failed 'Update-Packages should fail when winget upgrade fails'
}

# ---------------------------------------------------------------------------
# Package list
# ---------------------------------------------------------------------------

function test_windows_packages_include_neovim {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text '"Neovim.Neovim"'
}

function test_windows_installs_codex_cli_with_official_installer {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'https://chatgpt.com/codex/install.ps1'
    Assert-Contains $text 'CODEX_NON_INTERACTIVE'
}

function test_installpackages_fails_when_winget_install_fails {
    $script:Dry = $false
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-Item -Path function:global:WingetHas -Value { return $false }
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallPackages 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'winget'
        Set-Item -Path function:global:WingetHas -Value $originalWingetHas
    }

    Assert-True $failed 'InstallPackages should fail when winget install fails'
}

function test_installpackages_installs_missing_winget_packages_individually {
    $script:Dry = $false
    $script:MissingWingetPackages = @('Git.Git', 'Neovim.Neovim')
    $script:InstallCalls = @()
    $originalWingetHas = (Get-Command WingetHas).ScriptBlock
    Set-Item -Path function:global:WingetHas -Value { param($id) return ($script:MissingWingetPackages -notcontains $id) }
    Set-CommandMock 'winget' {
        if ($args[0] -eq 'install') { $script:InstallCalls += ,($args -join ' ') }
        $global:LASTEXITCODE = 0
    }

    try {
        InstallPackages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-Item -Path function:global:WingetHas -Value $originalWingetHas
        Remove-Variable -Name MissingWingetPackages -Scope Script -ErrorAction SilentlyContinue
    }

    Assert-Equals 2 $script:InstallCalls.Count
    Assert-Contains $script:InstallCalls[0] 'install --id Git.Git --exact'
    Assert-Contains $script:InstallCalls[1] 'install --id Neovim.Neovim --exact'
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

function test_installai_fails_when_codebase_memory_update_fails {
    $script:Dry = $false
    $originalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return [pscustomobject]@{ Source = 'mock-codebase-memory-mcp' } }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'codebase-memory-mcp' { $global:LASTEXITCODE = 1 }

    $failed = $false
    try {
        InstallAi -Update 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'codebase-memory-mcp'
        Clear-CommandMock 'Get-Command'
        Set-Item -Path function:global:InstallCodex -Value $originalInstallCodex
    }

    Assert-True $failed 'InstallAi should fail when codebase-memory-mcp update fails'
}

function test_installai_fails_when_codebase_memory_install_fails {
    $script:Dry = $false
    $originalInstallCodex = (Get-Command InstallCodex).ScriptBlock
    Set-Item -Path function:global:InstallCodex -Value { }
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codebase-memory-mcp') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'irm' { 'function global:codebase-memory-mcp { $global:LASTEXITCODE = 1 }; codebase-memory-mcp install' }

    $failed = $false
    try {
        InstallAi 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'irm'
        Clear-CommandMock 'Get-Command'
        Clear-CommandMock 'codebase-memory-mcp'
        Set-Item -Path function:global:InstallCodex -Value $originalInstallCodex
    }

    Assert-True $failed 'InstallAi should fail when codebase-memory-mcp install script fails'
}
