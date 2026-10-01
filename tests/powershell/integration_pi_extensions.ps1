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

$memoryEntry = Join-Path $release 'node_modules\pi-memory\index.ts'
if (-not (Test-Path -LiteralPath $memoryEntry -PathType Leaf)) { throw 'pi-memory entrypoint missing' }
if (-not (Get-Content -Raw -LiteralPath $memoryEntry).Contains('before_agent_start')) { throw 'pi-memory automatic recall missing' }
