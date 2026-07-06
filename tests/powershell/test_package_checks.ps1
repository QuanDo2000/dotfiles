# WingetHas with native-command mocks.

function TestTeardown {
    Clear-CommandMock 'winget'
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
