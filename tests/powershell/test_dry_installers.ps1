# Dry-mode paths for the installer functions: they should emit their banner
# message and return before touching external tools.

function TestSetup {
    $script:Dry = $true
    $script:Quiet = $false
}

function test_installscooppackages_dry_run_does_not_call_scoop {
    $script:Called = $false
    Set-CommandMock 'scoop' { $script:Called = $true }

    $output = InstallScoopPackages 6>&1 | Out-String

    Clear-CommandMock 'scoop'
    Assert-Contains $output 'Installing Scoop packages'
    Assert-False $script:Called 'scoop should not be invoked in dry run'
}

function test_installfnm_dry_run_does_not_call_fnm {
    $script:Called = $false
    Set-CommandMock 'fnm' { $script:Called = $true }

    $output = InstallFnm 6>&1 | Out-String

    Clear-CommandMock 'fnm'
    Assert-Contains $output 'Installing Node.js LTS'
    Assert-False $script:Called 'fnm should not be invoked in dry run'
}

function test_installai_dry_run_does_not_call_npm {
    $script:Called = $false
    Set-CommandMock 'npm' { $script:Called = $true }

    $output = InstallAi 6>&1 | Out-String

    Clear-CommandMock 'npm'
    Assert-Contains $output 'Installing agent CLIs'
    Assert-False $script:Called 'npm should not be invoked in dry run'
}

function test_installcodex_dry_run_does_not_download {
    $script:Called = $false
    Set-CommandMock 'Invoke-RestMethod' { $script:Called = $true }

    $output = InstallCodex 6>&1 | Out-String

    Clear-CommandMock 'Invoke-RestMethod'
    Assert-Contains $output 'Installing Codex CLI'
    Assert-False $script:Called 'Invoke-RestMethod should not be called in dry run'
}

function test_installpackages_dry_run_does_not_call_winget {
    $script:Called = $false
    Set-CommandMock 'winget' { $script:Called = $true }

    $output = InstallPackages 6>&1 | Out-String

    Clear-CommandMock 'winget'
    Assert-Contains $output 'Installing packages'
    Assert-False $script:Called 'winget should not be invoked in dry run'
}

function test_installextras_dry_run_chains_font_and_node {
    $output = InstallExtras 6>&1 | Out-String
    Assert-Contains $output 'Installing Scoop packages'
    Assert-Contains $output 'Installing Node.js LTS'
}
