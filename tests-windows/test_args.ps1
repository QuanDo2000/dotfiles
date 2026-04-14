# Argument parsing tests. ParseArgs mutates $script:Dry/$Force/$Quiet and
# returns the command name. Reset-DotfileState between tests is done by runner.

function test_parseargs_default_command_is_all {
    $cmd = ParseArgs @()
    Assert-Equals 'all' $cmd
}

function test_parseargs_dry_short_flag {
    $cmd = ParseArgs @('-d')
    Assert-True $script:Dry '-d should set Dry'
    Assert-Equals 'all' $cmd
}

function test_parseargs_dry_long_flag {
    $cmd = ParseArgs @('--dry')
    Assert-True $script:Dry '--dry should set Dry'
}

function test_parseargs_force_flag {
    $cmd = ParseArgs @('-f', 'symlinks')
    Assert-True $script:Force '-f should set Force'
    Assert-Equals 'symlinks' $cmd
}

function test_parseargs_quiet_flag {
    $cmd = ParseArgs @('-q', 'verify')
    Assert-True $script:Quiet '-q should set Quiet'
    Assert-Equals 'verify' $cmd
}

function test_parseargs_help_short_returns_sentinel {
    $script:Quiet = $true  # suppress ShowUsage output during test
    $cmd = ParseArgs @('-h')
    Assert-Equals '__help__' $cmd
}

function test_parseargs_positional_command_recognised {
    foreach ($c in 'packages', 'extras', 'symlinks', 'verify') {
        $script:Dry = $false
        $result = ParseArgs @($c)
        Assert-Equals $c $result
    }
}

function test_parseargs_combined_flags_and_command {
    $cmd = ParseArgs @('-d', '-f', '-q', 'packages')
    Assert-True $script:Dry 'Dry set'
    Assert-True $script:Force 'Force set'
    Assert-True $script:Quiet 'Quiet set'
    Assert-Equals 'packages' $cmd
}
