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
