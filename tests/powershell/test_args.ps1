# PowerShell's native parameter binder handles options and the command.
function test_parameter_binder_dispatches_dry_command {
    $output = pwsh -NoProfile -File $script:DotfileScript packages --dry 6>&1 | Out-String
    Assert-Equals 0 $LASTEXITCODE
    Assert-Contains $output 'Installing packages'

    $output = pwsh -NoProfile -File $script:DotfileScript update ai --dry 6>&1 | Out-String
    Assert-Equals 0 $LASTEXITCODE
    Assert-Contains $output 'Updating AI tools and configs'
    Assert-Contains $output 'Installing agent CLIs'
    Assert-False ($output -like '*Installing packages*') 'AI update should skip system packages'
    Assert-False ($output -like '*Neovim plugins*') 'AI update should skip Neovim plugins'
}

function test_upgrade_command_dry_run_dispatches_without_repo_or_setup {
    $output = pwsh -NoProfile -File $script:DotfileScript upgrade --dry 6>&1 | Out-String
    Assert-Equals 0 $LASTEXITCODE
    Assert-Contains $output 'Would run: winget upgrade --all'
    Assert-False ($output -like '*Updating dotfiles repo*') 'native upgrade must not pull the repo'
    Assert-False ($output -like '*Installing packages*') 'native upgrade must not run setup'
}

function test_symlinks_command_dry_run_dispatches_without_packages_or_repo_update {
    Initialize-TestEnv | Out-Null
    try {
        $env:DOTFILES_DIR = $script:RepoDir
        $output = pwsh -NoProfile -File $script:DotfileScript symlinks --dry 6>&1 | Out-String
        Assert-Equals 0 $LASTEXITCODE
        Assert-Contains $output 'Setting up symlinks'
        Assert-Contains $output 'Linking'
        Assert-False ($output -like '*Updating dotfiles repo*') 'standalone links must not pull the repo'
        Assert-False ($output -like '*Installing packages*') 'standalone links must not install packages'
        Assert-False (Test-Path (Join-Path $env:USERPROFILE '.local\bin\dotfile.ps1')) 'dry run must not create the CLI link'
    } finally {
        Clear-TestEnv
    }
}

function test_redundant_ai_and_verify_commands_are_not_exposed {
    foreach ($command in 'ai', 'verify') {
        $output = pwsh -NoProfile -File $script:DotfileScript $command --dry 6>&1 | Out-String
        Assert-Equals 1 $LASTEXITCODE
        Assert-Contains $output "Unknown command: $command"
    }
}

# Lock the short-form CLI aliases in place.
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

function test_elevated_symlink_uses_one_encoded_operation {
    $script:StartProcessArgs = @()
    $script:StartProcessVerb = ''
    Set-CommandMock 'Start-Process' {
        param($FilePath, $ArgumentList, $Verb, [switch]$Wait, [switch]$PassThru)
        $script:StartProcessArgs = @($ArgumentList)
        $script:StartProcessVerb = $Verb
        [pscustomobject]@{ ExitCode = 0 }
    }

    try {
        Invoke-ElevatedSymlink 'C:\source path\file' 'C:\destination path\file'
    } finally {
        Clear-CommandMock 'Start-Process'
    }

    Assert-True ($script:StartProcessArgs -contains '-EncodedCommand') 'one elevated operation should use an encoded command'
    Assert-Equals 'RunAs' $script:StartProcessVerb
}

function test_only_symlink_privilege_errors_require_elevation {
    Assert-True (Test-SymlinkPrivilegeError ([System.UnauthorizedAccessException]::new('Access denied'))) 'access failures may require elevation'
    Assert-True (Test-SymlinkPrivilegeError ([System.IO.IOException]::new('A required privilege is not held by the client.'))) 'Windows symlink privilege failures require elevation'
    Assert-False (Test-SymlinkPrivilegeError ([System.IO.IOException]::new('The disk is full.'))) 'unrelated filesystem failures must not trigger UAC'
}
