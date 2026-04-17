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

# Regression: PowerShell's parameter binder auto-adds common parameters
# (-Debug, -Verbose, ...) whenever any param has [Parameter(...)]. Without
# an explicit -Dry param, `-d` prefix-matches -Debug and is silently
# swallowed on the `pwsh -File dotfile.ps1 -d` path. Lock the explicit
# declaration + short-form aliases in place.
function test_script_declares_flag_params_with_short_aliases {
    $cmd = Get-Command $script:DotfileScript
    foreach ($pair in @(
            @{ Name = 'Dry';   Alias = 'd' },
            @{ Name = 'Force'; Alias = 'f' },
            @{ Name = 'Quiet'; Alias = 'q' },
            @{ Name = 'Help';  Alias = 'h' }
        )) {
        $p = $cmd.Parameters[$pair.Name]
        Assert-True ($null -ne $p) "$($pair.Name) param declared"
        if ($p) {
            Assert-True ($p.Aliases -contains $pair.Alias) `
                "$($pair.Name) has short alias -$($pair.Alias)"
        }
    }
}
