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

function test_update_packages_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    try {
        $output = Update-Packages 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'Would run: scoop update *'
    Assert-False $called 'scoop should not be invoked in dry run'
}

# ---------------------------------------------------------------------------
# Package list
# ---------------------------------------------------------------------------

function test_windows_packages_include_gleam {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text '"main/gleam"'
}
