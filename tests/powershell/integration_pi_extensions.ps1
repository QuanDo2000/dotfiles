$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'dotfile.ps1') -NoMain
$script:DotfilesDir = $repo
$script:Dry = $false

$pins = Get-PiExtensionsPins
$release = Join-Path $env:USERPROFILE ".pi\agent\locked-extensions\releases\$($pins.releaseId)"
if ($env:PI_EXTENSIONS_ARCHIVE_URL) {
    $archive = Join-Path $env:RUNNER_TEMP 'pi-extensions.tar.gz'
    $staging = "$release.staging"
    Remove-Item -LiteralPath $archive, $staging, $release -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Invoke-WebRequest -Uri $env:PI_EXTENSIONS_ARCHIVE_URL -OutFile $archive
    if ((Get-FileSha256 $archive) -ne $env:PI_EXTENSIONS_ARCHIVE_SHA256) { throw 'Pi extension archive checksum mismatch' }
    tar -xzf $archive -C $staging
    if ($LASTEXITCODE -ne 0) { throw 'Pi extension archive extraction failed' }
    if (-not (Test-PiExtensionsRelease $staging $pins)) { throw 'Extracted Pi extension release validation failed' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $release) | Out-Null
    Move-Item -LiteralPath $staging -Destination $release
} else {
    InstallPiExtensions
}
if (-not (Test-PiExtensionsRelease $release $pins)) { throw 'Pi extension release validation failed' }

$env:PI_EXTENSIONS_RELEASE = $release
try {
    & node -e "const D=require(process.env.PI_EXTENSIONS_RELEASE+'/node_modules/better-sqlite3');const d=new D(':memory:');d.prepare('select 1').get();d.close()"
    if ($LASTEXITCODE -ne 0) { throw 'better-sqlite3 smoke test failed' }
} finally {
    Remove-Item Env:PI_EXTENSIONS_RELEASE -ErrorAction SilentlyContinue
}
