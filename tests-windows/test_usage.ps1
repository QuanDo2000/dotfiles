# ShowUsage text tests — cheap sanity checks on the help output.

function test_showusage_mentions_all_commands {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    foreach ($cmd in 'all', 'packages', 'extras', 'symlinks', 'verify') {
        Assert-Contains $output $cmd
    }
}

function test_showusage_mentions_flags {
    # ShowUsage uses Write-Host; capture the Information stream (6) to inspect it.
    $output = ShowUsage 6>&1 | Out-String
    Assert-Contains $output '--dry'
    Assert-Contains $output '--force'
    Assert-Contains $output '--quiet'
    Assert-Contains $output '--help'
}
