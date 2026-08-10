$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'dotfile.ps1') -NoMain
$script:DotfilesDir = $repo
$script:Dry = $false

InstallPiExtensions
$pins = Get-PiExtensionsPins
$release = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$($pins.releaseId)"
if (-not (Test-PiExtensionsRelease $release $pins)) { throw 'Pi extension release validation failed' }

$env:PI_EXTENSIONS_RELEASE = $release
try {
    & node -e "const D=require(process.env.PI_EXTENSIONS_RELEASE+'/node_modules/better-sqlite3');const d=new D(':memory:');d.prepare('select 1').get();d.close()"
    if ($LASTEXITCODE -ne 0) { throw 'better-sqlite3 smoke test failed' }
} finally {
    Remove-Item Env:PI_EXTENSIONS_RELEASE -ErrorAction SilentlyContinue
}
