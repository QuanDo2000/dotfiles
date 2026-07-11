# Runner behavior tests.

function test_runner_accepts_multiple_test_files {
    $output = & pwsh (Join-Path $PSScriptRoot 'runner.ps1') test_args.ps1 test_usage.ps1 2>&1 | Out-String

    Assert-Contains $output '--- test_args.ps1 ---'
    Assert-Contains $output '--- test_usage.ps1 ---'
}
