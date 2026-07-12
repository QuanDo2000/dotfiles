$ErrorActionPreference = 'Stop'

$dotfile = Join-Path $PSScriptRoot '..\..\dotfile.ps1'
. $dotfile -NoMain
$nvim = Get-NeovimCommand
if (-not $nvim) { throw 'nvim executable not found' }

$root = Join-Path $env:RUNNER_TEMP 'lazyvim-integration'
if (Test-Path -LiteralPath $root) { Remove-Item -Recurse -Force $root }
$env:XDG_CONFIG_HOME = Join-Path $root 'config'
$env:XDG_DATA_HOME = Join-Path $root 'data'
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME, $env:XDG_DATA_HOME | Out-Null

$config = Join-Path $env:XDG_CONFIG_HOME 'nvim'
Copy-Item -Recurse (Join-Path $PSScriptRoot '..\..\config\shared\config\nvim') $config

& $nvim --headless '+Lazy! sync' '+qa'
if ($LASTEXITCODE -ne 0) { throw 'LazyVim sync failed' }

$dataPath = (& $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" '+qa' 2>$null) -join ''
$lazyRoot = Join-Path $dataPath.Trim() 'lazy'
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'lazy.nvim'))) { throw 'lazy.nvim was not installed' }
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'LazyVim'))) { throw 'LazyVim was not installed' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'fff.nvim')) { throw 'fff.nvim must stay disabled on Windows' }
