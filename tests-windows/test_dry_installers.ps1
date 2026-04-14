# Dry-mode paths for the installer functions: they should emit their banner
# message and return before touching external tools.

function TestSetup {
    $script:Dry = $true
    $script:Quiet = $false
}

function test_installfont_dry_run_does_not_call_scoop {
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }

    $output = InstallFont 6>&1 | Out-String

    Clear-CommandMock 'scoop'
    Assert-Contains $output 'Installing FiraCode'
    Assert-False $called 'scoop should not be invoked in dry run'
}

function test_installfnm_dry_run_does_not_call_fnm {
    $called = $false
    Set-CommandMock 'fnm' { $script:called = $true }

    $output = InstallFnm 6>&1 | Out-String

    Clear-CommandMock 'fnm'
    Assert-Contains $output 'Installing Node.js LTS'
    Assert-False $called 'fnm should not be invoked in dry run'
}

function test_installtreesitter_dry_run_does_not_call_npm {
    $called = $false
    Set-CommandMock 'npm' { $script:called = $true }

    $output = InstallTreeSitter 6>&1 | Out-String

    Clear-CommandMock 'npm'
    Assert-Contains $output 'Installing tree-sitter CLI'
    Assert-False $called 'npm should not be invoked in dry run'
}

function test_installpackages_dry_run_does_not_call_winget {
    $called = $false
    Set-CommandMock 'winget' { $script:called = $true }

    $output = InstallPackages 6>&1 | Out-String

    Clear-CommandMock 'winget'
    Assert-Contains $output 'Installing packages'
    Assert-False $called 'winget should not be invoked in dry run'
}

function test_installneovimnightly_dry_run_does_not_download {
    $called = $false
    Set-CommandMock 'Invoke-WebRequest' { $script:called = $true }

    $output = InstallNeovimNightly 6>&1 | Out-String

    Clear-CommandMock 'Invoke-WebRequest'
    Assert-Contains $output 'Checking Neovim nightly'
    Assert-False $called 'Invoke-WebRequest should not be called in dry run'
}

function test_installextras_dry_run_chains_three_installers {
    $output = InstallExtras 6>&1 | Out-String
    Assert-Contains $output 'Installing FiraCode'
    Assert-Contains $output 'Installing Node.js LTS'
    Assert-Contains $output 'Installing tree-sitter CLI'
}
