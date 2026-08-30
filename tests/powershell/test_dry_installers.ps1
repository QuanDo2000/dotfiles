# Dry-mode paths for installer functions must return before external tools.

function TestSetup {
    $script:Dry = $true
    $script:Quiet = $false
}

function test_installers_dry_run_before_external_commands {
    $cases = @(
        @{ Command = 'Invoke-WebRequest'; Function = 'InstallFiraCodeNerdFont'; Banner = 'Installing FiraCode Nerd Font' }
        @{ Command = 'fnm'; Function = 'InstallFnm'; Banner = 'Installing Node.js LTS' }
        @{ Command = 'npm'; Function = 'InstallAi'; Banner = 'Installing agent CLIs' }
        @{ Command = 'Invoke-RestMethod'; Function = 'InstallCodex'; Banner = 'Installing Codex CLI' }
        @{ Command = 'winget'; Function = 'InstallPackages'; Banner = 'Installing packages' }
    )

    foreach ($case in $cases) {
        $script:Called = $false
        Set-CommandMock $case.Command { $script:Called = $true }
        try {
            $installer = $case.Function
            $output = & $installer 6>&1 | Out-String
        } finally {
            Clear-CommandMock $case.Command
        }
        Assert-Contains $output $case.Banner
        Assert-False $script:Called "$($case.Command) should not be called in dry run"
    }
}
