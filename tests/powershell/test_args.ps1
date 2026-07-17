# PowerShell's native parameter binder handles options and the command.
function test_parameter_binder_dispatches_dry_command {
    $output = pwsh -NoProfile -File $script:DotfileScript packages --dry 6>&1 | Out-String
    Assert-Equals 0 $LASTEXITCODE
    Assert-Contains $output 'Installing packages'
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
