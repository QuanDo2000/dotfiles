$ErrorActionPreference = 'Stop'

$nvim = (Get-Command nvim -ErrorAction SilentlyContinue).Source
if (-not $nvim) {
    $nvim = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nvim.exe'
}
if (-not (Test-Path -LiteralPath $nvim)) { throw 'nvim executable not found' }

$config = Join-Path $env:LOCALAPPDATA 'nvim'
if (Test-Path -LiteralPath $config) { Remove-Item -Recurse -Force $config }
Copy-Item -Recurse (Join-Path $PSScriptRoot '..\..\config\shared\config\nvim') $config

& $nvim --headless '+Lazy! sync' '+qa'
if ($LASTEXITCODE -ne 0) { throw 'LazyVim sync failed' }

$dataPath = (& $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" '+qa' 2>$null) -join ''
$lazyRoot = Join-Path $dataPath.Trim() 'lazy'
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'lazy.nvim'))) { throw 'lazy.nvim was not installed' }
if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot 'LazyVim'))) { throw 'LazyVim was not installed' }
if (Test-Path -LiteralPath (Join-Path $lazyRoot 'fff.nvim')) { throw 'fff.nvim must stay disabled on Windows' }
