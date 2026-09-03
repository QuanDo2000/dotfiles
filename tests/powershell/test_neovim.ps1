# Windows Neovim synchronization tests.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

function test_neovim_plugin_sync_verifies_installed_directories {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $lazyRoot = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy'
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $env:DOTFILE_NVIM_SYNC = 'previous'
    $script:SeenNvimSync = $null
    $script:NvimCalls = @()
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-CommandMock 'nvim' {
        $script:NvimCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -like '*stdpath*') {
            Join-Path $env:LOCALAPPDATA 'nvim-data'
        } else {
            $script:SeenNvimSync = $env:DOTFILE_NVIM_SYNC
            'RAW_NEOVIM_SYNC_OK'
        }
    }

    try {
        Assert-Throws { Sync-NeovimPlugins } 'missing core plugin directories must fail setup'
        New-Item -ItemType Directory -Force -Path (Join-Path $lazyRoot 'lazy.nvim'), (Join-Path $lazyRoot 'snacks.nvim') | Out-Null
        $installedOutput = Sync-NeovimPlugins 3>&1 | Out-String
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
    }

    Assert-Equals '1' $script:SeenNvimSync
    Assert-Equals 'previous' $env:DOTFILE_NVIM_SYNC
    Assert-Contains $script:NvimCalls[2] 'plugins(false)'
    Assert-Contains $script:NvimCalls[2] 'sync.tools()'
    Assert-Contains $script:NvimCalls[2] 'sync.parsers()'
    Assert-False ($installedOutput -like '*Neovim plugin sync did not install*') 'installed directories should satisfy plugin sync verification'
    Remove-Item Env:DOTFILE_NVIM_SYNC
}

function test_neovim_plugin_sync_skips_full_restore_when_runtime_is_current {
    $script:Dry = $false
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $dataPath = Join-Path $env:LOCALAPPDATA 'nvim-data'
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    $script:NvimCalls = @()
    $script:ProbeSync = $null
    $env:DOTFILE_NVIM_SYNC = '1'
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-CommandMock 'nvim' {
        $script:NvimCalls += ,($args -join ' ')
        $global:LASTEXITCODE = 0
        if (($args -join ' ') -like '*stdpath*') { return $dataPath }
        $script:ProbeSync = $env:DOTFILE_NVIM_SYNC
        'RAW_NEOVIM_SYNC_CURRENT'
    }

    try {
        Sync-NeovimPlugins
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
    }

    Assert-Equals 2 $script:NvimCalls.Count
    Assert-Contains $script:NvimCalls[0] 'stdpath'
    Assert-Equals '0' $script:ProbeSync
    Assert-Equals '1' $env:DOTFILE_NVIM_SYNC
    Assert-Contains $script:NvimCalls[1] 'runtime_complete()'
    Assert-False ($script:NvimCalls[1].Contains("plugins(false)")) 'current runtime must skip full plugin restore'
    Remove-Item Env:DOTFILE_NVIM_SYNC
}

function test_windows_lazy_sync_prepares_parent_and_fetches_locked_commit {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\config\nvim\init.lua')
    Assert-Contains $config 'vim.fn.mkdir(vim.fs.dirname(lazypath), "p")'
    Assert-Contains $config '{ "git", "-C", lazypath, "fetch", "--filter=blob:none", "origin" }'
}

function test_neovim_plugin_sync_fails_without_success_marker {
    $script:Dry = $false
    $originalGetNeovim = (Get-Command Get-NeovimCommand).ScriptBlock
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-CommandMock 'nvim' {
        $global:LASTEXITCODE = 0
        'Lazy build failed'
    }

    try {
        Assert-Throws { Sync-NeovimPlugins } 'missing sync marker must fail setup'
    } finally {
        Clear-CommandMock 'nvim'
        Set-FunctionMock 'Get-NeovimCommand' $originalGetNeovim
    }
}

function test_getneovimcommand_uses_winget_fallback {
    $env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
    $nvim = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nvim.exe'
    New-Item -ItemType Directory -Force -Path (Split-Path $nvim -Parent) | Out-Null
    New-Item -ItemType File -Path $nvim | Out-Null
    Set-CommandMock 'Get-Command' { return $null }

    try {
        $result = Get-NeovimCommand
    } finally {
        Clear-CommandMock 'Get-Command'
    }

    Assert-Equals $nvim $result
}
