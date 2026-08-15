$ErrorActionPreference = 'Stop'

$dotfile = Join-Path $PSScriptRoot '..\..\dotfile.ps1'
. $dotfile -NoMain
$nvim = Get-NeovimCommand
if (-not $nvim) { throw 'nvim executable not found' }

$root = Join-Path $env:RUNNER_TEMP 'neovim-integration'
if (Test-Path -LiteralPath $root) { Remove-Item -Recurse -Force $root }
$env:XDG_CONFIG_HOME = Join-Path $root 'config'
$env:XDG_DATA_HOME = Join-Path $root 'data'
$env:XDG_CACHE_HOME = Join-Path $root 'cache'
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME, $env:XDG_DATA_HOME, $env:XDG_CACHE_HOME | Out-Null

$config = Join-Path $env:XDG_CONFIG_HOME 'nvim'
Copy-Item -Recurse (Join-Path $PSScriptRoot '..\..\config\shared\config\nvim') $config
$prettier = Join-Path $env:XDG_DATA_HOME 'nvim\mason\packages\prettier'
if (Test-Path -LiteralPath $prettier) { throw 'prettier must start missing from isolated Mason root' }

$env:DOTFILE_NVIM_SYNC = '1'
try {
    $syncOutput = (& $nvim --headless "+lua require('config.sync').plugins(false); require('config.sync').tools(); print('RAW_NEOVIM_SYNC_OK')" '+qa' 2>&1) -join "`n"
    $syncExitCode = $LASTEXITCODE
} finally {
    Remove-Item Env:DOTFILE_NVIM_SYNC -ErrorAction SilentlyContinue
}
if ($syncExitCode -ne 0 -or -not $syncOutput.Contains('RAW_NEOVIM_SYNC_OK')) {
    throw "Neovim plugin or tool sync failed: $syncOutput"
}
$env:RAW_CONFIG_TEST = (Join-Path $PSScriptRoot '..\nvim\raw_config.lua').Replace('\', '/')
$rawOutput = (& $nvim --headless -c 'lua dofile(vim.env.RAW_CONFIG_TEST)' '+qa' 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $rawOutput.Contains('RAW_CONFIG_OK')) {
    throw "Raw Neovim config check failed: $rawOutput"
}

$dataPath = (& $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" '+qa' 2>$null) -join ''
$lazyRoot = Join-Path $dataPath.Trim() 'lazy'
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'lazy.nvim'))) { throw 'lazy.nvim was not installed' }
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'snacks.nvim'))) { throw 'snacks.nvim was not installed' }
if (-not (Test-Path -LiteralPath (Join-Path $dataPath.Trim() 'mason\packages\prettier'))) { throw 'prettier was not installed' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'fff.nvim')) { throw 'fff.nvim must stay disabled on Windows' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'LazyVim')) { throw 'LazyVim must not be installed' }
