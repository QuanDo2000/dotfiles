# ShowUsage text tests — cheap sanity checks on the help output.

function test_showusage_mentions_commands_and_flags {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    foreach ($value in 'all', 'packages', 'doctor', 'verify', 'update', '--dry', '--force', '--quiet', '--help') {
        Assert-Contains $output $value
    }
    Assert-Contains $output 'packages    Install all managed packages only'
    Assert-False ($output -match '(?m)^\s+ai\s+') 'ShowUsage should not expose a standalone ai command'
}
