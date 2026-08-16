# PowerShell test harness regression coverage.

function test_clear_test_env_restores_home_independently {
    $oldUserProfile = $env:USERPROFILE
    $oldHome = $env:HOME
    try {
        $env:USERPROFILE = 'original-userprofile'
        $env:HOME = 'original-home'
        Initialize-TestEnv | Out-Null
        Clear-TestEnv
        Assert-Equals 'original-userprofile' $env:USERPROFILE
        Assert-Equals 'original-home' $env:HOME
    } finally {
        if ($null -eq $oldUserProfile) { Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue } else { $env:USERPROFILE = $oldUserProfile }
        if ($null -eq $oldHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue } else { $env:HOME = $oldHome }
    }
}

function test_runner_reports_teardown_failure {
    $temp = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-runner-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $fixture = Join-Path $temp 'test_teardown.ps1'
    @'
function test_body_passes { }
function TestTeardown { throw "cleanup failed" }
'@ | Set-Content -LiteralPath $fixture
    try {
        $output = & pwsh -NoProfile (Join-Path $PSScriptRoot 'runner.ps1') $fixture 2>&1 | Out-String
        Assert-Equals 1 $LASTEXITCODE
        Assert-Contains $output 'TestTeardown FAILED: cleanup failed'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function test_assert_contains_treats_wildcards_literally {
    $before = $script:Errors.Count
    Assert-Contains 'nothing relevant except p' '[projects.keep]'
    $after = $script:Errors.Count
    $script:Errors.RemoveAt($script:Errors.Count - 1)
    Assert-Equals ($before + 1) $after
}

function test_runner_continues_after_test_file_load_failure {
    $temp = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-runner-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $broken = Join-Path $temp 'test_broken.ps1'
    $passing = Join-Path $temp 'test_passing.ps1'
    'function test_leaked_from_broken_file { }; throw "load failed"' | Set-Content -LiteralPath $broken
    'function test_body_passes { }' | Set-Content -LiteralPath $passing
    try {
        $output = & pwsh -NoProfile (Join-Path $PSScriptRoot 'runner.ps1') $broken $passing 2>&1 | Out-String
        Assert-Equals 1 $LASTEXITCODE
        Assert-Contains $output 'LOAD FAILED'
        Assert-Contains $output 'PASS  test_body_passes'
        Assert-False ($output.Contains('test_leaked_from_broken_file')) 'partially loaded tests should not leak'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function test_runner_reports_explicit_skips {
    $temp = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-runner-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $fixture = Join-Path $temp 'test_skip.ps1'
    'function test_body_skips { Skip-Test "missing capability" }' | Set-Content -LiteralPath $fixture
    try {
        $output = & pwsh -NoProfile (Join-Path $PSScriptRoot 'runner.ps1') $fixture 2>&1 | Out-String
        Assert-Equals 0 $LASTEXITCODE
        Assert-Contains $output 'SKIP  test_body_skips: missing capability'
        Assert-Contains $output '1 skipped'
        Assert-Contains $output '0 passed'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
