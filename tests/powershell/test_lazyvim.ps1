# Windows LazyVim synchronization tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_lazyvim_sync_verifies_installed_directories {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $originalGetDataPath = (Get-Command Get-NeovimDataPath).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-FunctionMock 'Get-NeovimDataPath' { Join-Path $env:LOCALAPPDATA 'nvim-data' }
    Set-CommandMock 'nvim' { $global:LASTEXITCODE = 0 }

    try {
        $output = Sync-LazyVim 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
        Set-FunctionMock 'Get-NeovimDataPath' $originalGetDataPath
    }

    Assert-Contains $output 'LazyVim sync did not install'
}

function test_lazyvim_sync_accepts_installed_directories {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $lazyRoot = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy'
    New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'lazy.nvim') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'LazyVim') | Out-Null
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $originalGetDataPath = (Get-Command Get-NeovimDataPath).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-FunctionMock 'Get-NeovimDataPath' { Join-Path $env:LOCALAPPDATA 'nvim-data' }
    Set-CommandMock 'nvim' { $global:LASTEXITCODE = 0 }

    try {
        $output = Sync-LazyVim 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
        Set-FunctionMock 'Get-NeovimDataPath' $originalGetDataPath
    }

    Assert-False ($output -like '*LazyVim sync did not install*') 'installed directories should satisfy LazyVim sync verification'
}

function test_lazyvim_sync_uses_winget_neovim_fallback {
    $text = Get-Content -Raw $script:DotfileScript
    Assert-Contains $text 'Microsoft\WinGet\Links\nvim.exe'
    Assert-Contains $text 'Microsoft\WinGet\Packages'
    Assert-Contains $text 'Neovim\bin\nvim.exe'
    Assert-Contains $text '$env:ProgramFiles'
    Assert-Contains $text 'Get-ChildItem'
    Assert-Contains $text 'Get-NeovimCommand'
    Assert-Contains $text 'Get-NeovimDataPath'
    Assert-Contains $text 'vim.fn.stdpath'
    Assert-False ($text -like '*Join-Path $env:LOCALAPPDATA "nvim-data\lazy"*') 'sync verification should not hard-code Neovim data path'
}

function test_update_packages_syncs_lazyvim {
    $script:Dry = $false
    $script:LazySynced = $false
    Set-CommandMock 'winget' { $global:LASTEXITCODE = 0 }
    $originalInstallAi = (Get-Command InstallAi).ScriptBlock
    $originalSyncLazyVim = (Get-Command Sync-LazyVim).ScriptBlock
    Set-FunctionMock 'InstallAi' { }
    Set-FunctionMock 'Sync-LazyVim' { $script:LazySynced = $true }

    try {
        Update-Packages 6>&1 | Out-Null
    } finally {
        Clear-CommandMock 'winget'
        Set-FunctionMock 'InstallAi' $originalInstallAi
        Set-FunctionMock 'Sync-LazyVim' $originalSyncLazyVim
    }

    Assert-True $script:LazySynced 'Update-Packages should sync LazyVim'
}
