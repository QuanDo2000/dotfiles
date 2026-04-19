# Tests for Gleam install helpers in dotfile.ps1.

# Junction is a Windows-only concept; on Linux pwsh use SymbolicLink instead
# so the tests can exercise the same code path on both platforms.
$script:_LinkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

# ---------------------------------------------------------------------------
# Get-GleamTargetTriple
# ---------------------------------------------------------------------------

function test_get_gleam_target_triple_returns_msvc_on_x64 {
    # On the test runner (always 64-bit), this should resolve.
    $result = Get-GleamTargetTriple
    Assert-Equals 'x86_64-pc-windows-msvc' $result
}

# ---------------------------------------------------------------------------
# Get-GleamLatestRelease
# ---------------------------------------------------------------------------

function test_get_gleam_latest_release_uses_passed_json {
    # If a JSON arg is passed, the function returns it verbatim and never
    # calls InvokeRestMethodRetry. We verify this indirectly: pass a JSON
    # string that would be invalid for the API, and confirm it comes back
    # unchanged (proof that no network call was made to replace it).
    $result = Get-GleamLatestRelease -Json '{"tag_name": "v1.15.4"}'
    Assert-Equals '{"tag_name": "v1.15.4"}' $result
}

# ---------------------------------------------------------------------------
# Get-GleamCurrentInstalledVersion
# ---------------------------------------------------------------------------

function test_get_gleam_current_installed_version_none {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals '' $result
}

function test_get_gleam_current_installed_version_ours_returns_tag {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $versioned = Join-Path $programs 'gleam-v1.15.4'
    New-Item -ItemType Directory -Force -Path $versioned | Out-Null
    New-Item -ItemType $script:_LinkType -Path (Join-Path $programs 'gleam') -Target $versioned | Out-Null

    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals 'v1.15.4' $result
}

function test_get_gleam_current_installed_version_foreign_returns_empty {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $foreign = Join-Path $script:_TestTmp.FullName 'elsewhere'
    New-Item -ItemType Directory -Force -Path $foreign | Out-Null
    New-Item -ItemType Directory -Force -Path $programs | Out-Null
    New-Item -ItemType $script:_LinkType -Path (Join-Path $programs 'gleam') -Target $foreign | Out-Null

    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals '' $result
}

# ---------------------------------------------------------------------------
# Install-Erlang
# ---------------------------------------------------------------------------

function test_install_erlang_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    # Make erl unfindable: replace PATH with a dir that has no `erl`
    $origPath = $env:PATH
    $env:PATH = $script:_TestTmp.FullName

    try {
        $output = Install-Erlang 6>&1 | Out-String
    } finally {
        $env:PATH = $origPath
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'Erlang/OTP not found'
    Assert-False $called 'scoop should not be invoked in dry run'
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
# Install-Gleam
# ---------------------------------------------------------------------------

function test_install_gleam_dry_run {
    $script:Dry = $true
    $env:LOCALAPPDATA = $script:_TestTmp.FullName

    # Stub the dependency installs so the dry-run test doesn't need scoop/erl.
    # Capture ScriptBlock into plain variables before stubbing so the finally
    # block can reliably restore them (property access on FunctionInfo can
    # return empty in some scopes).
    $sbErlang = (Get-Item 'function:Install-Erlang').ScriptBlock
    $sbRebar3 = (Get-Item 'function:Install-Rebar3').ScriptBlock
    Set-Item -Path 'function:script:Install-Erlang' -Value { }
    Set-Item -Path 'function:script:Install-Rebar3' -Value { }

    try {
        $output = Install-Gleam 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Erlang' -Value $sbErlang
        Set-Item -Path 'function:script:Install-Rebar3' -Value $sbRebar3
    }

    Assert-Contains $output 'Installing Gleam'
    Assert-Contains $output 'Finished'
    $created = Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\gleam-v1.15.4')
    Assert-False $created 'dry run should not create install dir'
}

function test_install_gleam_already_installed_short_circuits {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $versioned = Join-Path $programs 'gleam-v1.15.4'
    New-Item -ItemType Directory -Force -Path $versioned | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $versioned 'gleam.exe') | Out-Null

    # Cross-platform link type — junction on Windows, symlink on Linux.
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path (Join-Path $programs 'gleam') -Target $versioned | Out-Null

    # Capture ScriptBlocks into plain variables before stubbing so the finally
    # block can reliably restore them.
    $sbErlang        = (Get-Item 'function:Install-Erlang').ScriptBlock
    $sbRebar3        = (Get-Item 'function:Install-Rebar3').ScriptBlock
    $sbLatestRelease = (Get-Item 'function:Get-GleamLatestRelease').ScriptBlock
    Set-Item -Path 'function:script:Install-Erlang' -Value { }
    Set-Item -Path 'function:script:Install-Rebar3' -Value { }
    Set-Item -Path 'function:script:Get-GleamLatestRelease' -Value {
        param([string]$Json = $null)
        return '{"tag_name": "v1.15.4", "assets": []}'
    }

    try {
        $output = Install-Gleam 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Install-Erlang' -Value $sbErlang
        Set-Item -Path 'function:script:Install-Rebar3' -Value $sbRebar3
        Set-Item -Path 'function:script:Get-GleamLatestRelease' -Value $sbLatestRelease
    }

    Assert-Contains $output 'Already installed Gleam v1.15.4'
}

# ---------------------------------------------------------------------------
# Update-Gleam
# ---------------------------------------------------------------------------

function test_update_gleam_no_op_when_not_installed {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $output = Update-Gleam 6>&1 | Out-String
    Assert-Equals '' $output.Trim()
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
# Update-Languages
# ---------------------------------------------------------------------------

function test_update_languages_calls_update_gleam_only {
    # Stub Update-Gleam to record invocation and produce a known marker.
    $sbUpdateGleam = (Get-Command Update-Gleam).ScriptBlock
    Set-Item -Path 'function:script:Update-Gleam' -Value { Info 'STUB Update-Gleam called' }

    try {
        $output = Update-Languages 6>&1 | Out-String
    } finally {
        Set-Item -Path 'function:script:Update-Gleam' -Value $sbUpdateGleam
    }

    Assert-Contains $output 'STUB Update-Gleam called'
}
