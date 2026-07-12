# Windows AI tool installer tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_windows_installs_codex_cli_with_official_installer {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'https://chatgpt.com/codex/install.ps1'
    Assert-Contains $text 'CODEX_NON_INTERACTIVE'
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

function test_installcodex_fails_when_installer_exits_nonzero {
    $script:Dry = $false
    Set-CommandMock 'Get-Command' {
        param($Name)
        if ($Name -eq 'codex') { return $null }
        return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    Set-CommandMock 'Invoke-RestMethod' { '$global:LASTEXITCODE = 1' }

    $failed = $false
    try {
        InstallCodex 6>&1 | Out-Null
    } catch {
        $failed = $true
    } finally {
        Clear-CommandMock 'Invoke-RestMethod'
        Clear-CommandMock 'Get-Command'
    }

    Assert-True $failed 'InstallCodex should fail when installer exits nonzero'
}
