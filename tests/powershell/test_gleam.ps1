# Tests for Gleam install helpers in dotfile.ps1.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

# ---------------------------------------------------------------------------
# Install-Rebar3
# ---------------------------------------------------------------------------

function test_install_rebar3_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    $origPath = $env:PATH
    $env:PATH = $script:_TestTmp.FullName

    try {
        $output = Install-Rebar3 6>&1 | Out-String
    } finally {
        $env:PATH = $origPath
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'rebar3 not found'
    Assert-False $called 'scoop should not be invoked in dry run'
}

# ---------------------------------------------------------------------------
# Install-Gleam (now a thin scoop wrapper)
# ---------------------------------------------------------------------------

function test_install_gleam_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    try {
        $output = Install-Gleam 6>&1 | Out-String
    } finally {
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'Installing Gleam'
    Assert-False $called 'scoop should not be invoked in dry run'
}

# ---------------------------------------------------------------------------
# Install-Languages
# ---------------------------------------------------------------------------

function test_install_languages_dispatches_gleam_only {
    $script:Dry = $true
    # Save the real Install-Gleam ScriptBlock so the stub doesn't leak.
    $sbInstallGleam = (Get-Command Install-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    try {
        $output = Install-Languages -Target 'gleam' 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Gleam' -Value $sbInstallGleam
    }

    Assert-Contains $output 'STUB Install-Gleam called'
}

function test_install_languages_unknown_fails {
    # Stub Fail to throw instead of calling exit so we can catch it in tests.
    $sbFail = (Get-Command Fail).ScriptBlock
    Set-Item -Path 'function:script:Fail' -Value { param($msg) throw "FAIL: $msg" }

    $threw = $false
    try {
        Install-Languages -Target 'java'
    } catch {
        $threw = $true
    } finally {
        Set-Item -Path 'function:script:Fail' -Value $sbFail
    }
    Assert-True $threw 'Install-Languages java should throw'
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
# Install-Languages skip messages
# ---------------------------------------------------------------------------

function test_install_languages_zig_emits_scoop_message {
    $output = Install-Languages -Target 'zig' 6>&1 | Out-String
    Assert-Contains $output 'scoop'
}

function test_install_languages_odin_emits_unsupported_message {
    $output = Install-Languages -Target 'odin' 6>&1 | Out-String
    Assert-Contains $output 'odin'
    Assert-Contains $output 'no Windows installer'
}

function test_install_languages_jank_emits_unsupported_message {
    $output = Install-Languages -Target 'jank' 6>&1 | Out-String
    Assert-Contains $output 'jank'
    Assert-Contains $output 'Linux/macOS only'
}

function test_install_languages_all_runs_gleam_and_skips_others {
    $sbInstallGleam = (Get-Command Install-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    try {
        $output = Install-Languages -Target 'all' 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Gleam' -Value $sbInstallGleam
    }

    Assert-Contains $output 'STUB Install-Gleam called'
    Assert-Contains $output 'Skipping zig'
    Assert-Contains $output 'Skipping odin'
    Assert-Contains $output 'Skipping jank'
}

function test_install_languages_empty_target_behaves_like_all {
    $sbInstallGleam = (Get-Command Install-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    try {
        $output = Install-Languages -Target '' 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Gleam' -Value $sbInstallGleam
    }

    Assert-Contains $output 'STUB Install-Gleam called'
    Assert-Contains $output 'Skipping zig'
    Assert-Contains $output 'Skipping odin'
    Assert-Contains $output 'Skipping jank'
}
