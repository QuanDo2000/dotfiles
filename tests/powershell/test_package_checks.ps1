# WingetHas / ScoopHas with native-command mocks.

function TestTeardown {
    Clear-CommandMock 'winget'
    Clear-CommandMock 'scoop'
}

function test_wingethas_true_when_exit_zero {
    Set-CommandMock 'winget' {
        $global:LASTEXITCODE = 0
        'Git.Git 2.0'
    }
    Assert-True (WingetHas 'Git.Git') 'WingetHas should return true on exit 0'
}

function test_wingethas_false_when_exit_nonzero {
    Set-CommandMock 'winget' {
        $global:LASTEXITCODE = 1
    }
    Assert-False (WingetHas 'Nonexistent.Package') 'WingetHas should return false on non-zero exit'
}

function test_scoophas_true_when_output_matches {
    Set-CommandMock 'scoop' {
        # Emulate scoop list's object output with a Name property.
        [pscustomobject]@{ Name = 'mingw' }
    }
    Assert-True (ScoopHas 'mingw') 'ScoopHas should match plain names'
}

function test_scoophas_handles_bucket_prefix {
    Set-CommandMock 'scoop' {
        [pscustomobject]@{ Name = 'ast-grep' }
    }
    # ScoopHas strips 'main/' bucket prefix before matching.
    Assert-True (ScoopHas 'main/ast-grep') 'ScoopHas should strip bucket prefix'
}

function test_scoophas_false_when_not_found {
    Set-CommandMock 'scoop' { }  # returns nothing
    Assert-False (ScoopHas 'absent-pkg') 'ScoopHas should return false when output empty'
}
