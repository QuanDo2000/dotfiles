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
