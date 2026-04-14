# Shared helpers for tests-windows. Dot-sourced by runner.ps1 before each test
# file. Mirrors the responsibilities of tests/helpers.sh on the Unix side.

$script:RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:DotfileScript = Join-Path $script:RepoDir 'windows\bin\dotfile.ps1'

# Load dotfile.ps1 functions without running elevation or main dispatch.
# Dot-sourced so $script:* variables and functions land in the caller's scope.
. $script:DotfileScript -NoMain

# --- Assertions ---------------------------------------------------------------
# Append failure messages to $script:Errors; runner inspects it to decide PASS/FAIL.

function Assert-Equals($Expected, $Actual) {
    if ($Expected -ne $Actual) {
        $script:Errors.Add("  Assert-Equals FAILED: expected '$Expected', got '$Actual'")
    }
}

function Assert-Contains($Haystack, $Needle) {
    if ($Haystack -notlike "*$Needle*") {
        $script:Errors.Add("  Assert-Contains FAILED: '$Haystack' does not contain '$Needle'")
    }
}

function Assert-True($Condition, $Message = 'condition was false') {
    if (-not $Condition) { $script:Errors.Add("  Assert-True FAILED: $Message") }
}

function Assert-False($Condition, $Message = 'condition was true') {
    if ($Condition) { $script:Errors.Add("  Assert-False FAILED: $Message") }
}

function Assert-FileExists($Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $script:Errors.Add("  Assert-FileExists FAILED: '$Path' does not exist")
    }
}

# --- Fixtures -----------------------------------------------------------------

# Reset all $script:* state owned by dotfile.ps1 to defaults.
function Reset-DotfileState {
    $script:Dry = $false
    $script:Quiet = $false
    $script:Force = $false
    $script:OverwriteAll = $false
    $script:BackupAll = $false
    $script:SkipAll = $false
}

# Create an isolated temp dir + fake HOME. Returns the temp dir path.
# Stashes originals in $script:_OrigHome / $script:_TestTmp for cleanup.
function Initialize-TestEnv {
    $script:_TestTmp = New-Item -ItemType Directory -Force -Path (Join-Path ([IO.Path]::GetTempPath()) ("dot_" + [Guid]::NewGuid().ToString('N')))
    $script:_OrigHome = $env:USERPROFILE
    $script:_OrigDotfiles = $env:DOTFILES_DIR
    $env:USERPROFILE = Join-Path $script:_TestTmp.FullName 'home'
    $env:HOME = $env:USERPROFILE
    $env:DOTFILES_DIR = Join-Path $env:USERPROFILE 'dotfiles'
    New-Item -ItemType Directory -Force -Path $env:USERPROFILE | Out-Null
    return $script:_TestTmp.FullName
}

# Shadow a native command with a PowerShell function. $ScriptBlock receives
# the mock's args; set $global:LASTEXITCODE inside it to simulate exit codes.
# Remove the shadow with `Remove-Item function:\<name>`.
function Set-CommandMock {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    Set-Item -Path "function:global:$Name" -Value $ScriptBlock
}

function Clear-CommandMock {
    param([Parameter(Mandatory)][string]$Name)
    Remove-Item "function:$Name" -ErrorAction SilentlyContinue
    Remove-Item "function:global:$Name" -ErrorAction SilentlyContinue
}

function Clear-TestEnv {
    $env:USERPROFILE = $script:_OrigHome
    $env:HOME = $script:_OrigHome
    $env:DOTFILES_DIR = $script:_OrigDotfiles
    if ($script:_TestTmp -and (Test-Path $script:_TestTmp.FullName)) {
        Remove-Item -Recurse -Force $script:_TestTmp.FullName -ErrorAction SilentlyContinue
    }
}
