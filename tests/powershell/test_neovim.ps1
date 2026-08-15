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
    Set-FunctionMock 'Get-NeovimCommand' { 'nvim' }
    Set-CommandMock 'nvim' {
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
    Assert-Contains (Get-Content -Raw $script:DotfileScript) "require('config.sync').plugins(false)"
    Assert-Contains (Get-Content -Raw $script:DotfileScript) "require('config.sync').tools()"
    Assert-False ($installedOutput -like '*Neovim plugin sync did not install*') 'installed directories should satisfy plugin sync verification'
    Remove-Item Env:DOTFILE_NVIM_SYNC
}

function test_windows_lazy_sync_prepares_parent_and_fetches_locked_commit {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\config\nvim\init.lua')
    Assert-Contains $config 'vim.fn.mkdir(vim.fs.dirname(lazypath), "p")'
    Assert-Contains $config '{ "git", "-C", lazypath, "fetch", "--filter=blob:none", "origin" }'
}

function test_windows_neovim_skips_nil_without_nix {
    $config = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\config\nvim\init.lua')
    $sync = Get-Content -Raw (Join-Path $script:RepoDir 'config\shared\config\nvim\lua\config\sync.lua')

    Assert-Contains $sync 'if vim.fn.has("win32") ~= 1 then'
    Assert-False ($sync.Contains('"bash-language-server"')) 'bash-language-server should remain platform-managed'
    Assert-False ($sync.Contains('"nil"')) 'nil should remain platform-managed'
    Assert-Contains $config 'if vim.fn.executable("nil") == 1 then'
    Assert-Contains $config 'nix = vim.fn.executable("nixfmt") == 1 and { "nixfmt" } or {}'
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

function test_windows_neovim_integration_executes_isolated_raw_check {
    $integration = Get-Content -Raw (Join-Path $script:RepoDir 'tests\powershell\integration_neovim.ps1')
    Assert-Contains $integration "-c 'lua dofile(vim.env.RAW_CONFIG_TEST)'"
    Assert-Contains $integration 'RAW_CONFIG_OK'
    Assert-Contains $integration '$env:XDG_CACHE_HOME = Join-Path $root ''cache'''
    Assert-Contains $integration '$env:RAW_CONFIG_PARSE_ONLY = ''1'''
    Assert-Contains $integration 'lazy.nvim was not installed'
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
