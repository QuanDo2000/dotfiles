# Tests for the opencode ponytail plugin installer in dotfile.ps1.
# Mirrors tests/bash/test_extras.sh's install_opencode_plugins coverage.

function TestSetup {
    Initialize-TestEnv | Out-Null
    Reset-DotfileState
}

function TestTeardown {
    Clear-CommandMock 'git'
    Clear-TestEnv
}

# --- opencode ---------------------------------------------------------------

function test_install_opencode_plugins_dry_run_does_not_clone {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'git' { $script:called = $true }

    $output = InstallOpencodePlugins 6>&1 | Out-String

    Assert-Contains $output 'Installing opencode plugins'
    Assert-False $called 'git should not be invoked in dry run'
}

function test_install_opencode_plugins_links_commands {
    # Fake git clone: drop a checkout with a command file so the link loop has
    # something to symlink.
    Set-CommandMock 'git' {
        $dest = $args[-1]
        New-Item -ItemType Directory -Force -Path (Join-Path $dest '.git') | Out-Null
        $cmdDir = Join-Path $dest '.opencode\command'
        New-Item -ItemType Directory -Force -Path $cmdDir | Out-Null
        '# c' | Set-Content -LiteralPath (Join-Path $cmdDir 'ponytail.md')
        $global:LASTEXITCODE = 0
    }

    try {
        InstallOpencodePlugins 6>&1 | Out-Null
    } catch {
        # Symlink creation needs admin/Developer Mode; skip if unavailable.
        if ($_.Exception.Message -match 'privilege|Administrator') { return }
        throw
    }

    $link = Join-Path $env:USERPROFILE '.config\opencode\command\ponytail.md'
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    Assert-True ($item -and $item.LinkType -eq 'SymbolicLink') 'command md should be symlinked'
}
