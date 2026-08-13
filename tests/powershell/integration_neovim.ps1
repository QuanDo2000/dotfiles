$ErrorActionPreference = 'Stop'

$dotfile = Join-Path $PSScriptRoot '..\..\dotfile.ps1'
. $dotfile -NoMain
$nvim = Get-NeovimCommand
if (-not $nvim) { throw 'nvim executable not found' }

$root = Join-Path $env:RUNNER_TEMP 'neovim-integration'
if (Test-Path -LiteralPath $root) { Remove-Item -Recurse -Force $root }
$env:XDG_CONFIG_HOME = Join-Path $root 'config'
$env:XDG_DATA_HOME = Join-Path $root 'data'
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME, $env:XDG_DATA_HOME | Out-Null

$config = Join-Path $env:XDG_CONFIG_HOME 'nvim'
Copy-Item -Recurse (Join-Path $PSScriptRoot '..\..\config\shared\config\nvim') $config

& $nvim --headless '+Lazy! restore' '+qa'
if ($LASTEXITCODE -ne 0) { throw 'Neovim plugin sync failed' }
& $nvim --headless "lua dofile('$((Join-Path $PSScriptRoot '..\nvim\raw_config.lua').Replace('\', '/'))')" '+qa'
if ($LASTEXITCODE -ne 0) { throw 'Raw Neovim config check failed' }

$dataPath = (& $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" '+qa' 2>$null) -join ''
$lazyRoot = Join-Path $dataPath.Trim() 'lazy'
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'lazy.nvim'))) { throw 'lazy.nvim was not installed' }
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'snacks.nvim'))) { throw 'snacks.nvim was not installed' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'fff.nvim')) { throw 'fff.nvim must stay disabled on Windows' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'LazyVim')) { throw 'LazyVim must not be installed' }
