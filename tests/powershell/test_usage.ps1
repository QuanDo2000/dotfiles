# ShowUsage text tests — cheap sanity checks on the help output.

function test_showusage_mentions_all_commands {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    foreach ($cmd in 'all', 'packages', 'doctor', 'verify', 'update') {
        Assert-Contains $output $cmd
    }
    Assert-Contains $output 'packages    Install all managed packages only'
    Assert-False ($output -match '(?m)^\s+ai\s+') 'ShowUsage should not expose a standalone ai command'
}

function test_showusage_mentions_flags {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    Assert-Contains $output '--dry'
    Assert-Contains $output '--force'
    Assert-Contains $output '--quiet'
    Assert-Contains $output '--help'
}
