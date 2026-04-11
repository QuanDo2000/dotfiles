$ErrorActionPreference = "Stop"

# Global variables
$script:Dry = $false
$script:Quiet = $false
$script:Force = $false
$script:DotfilesDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:RepoUrl = "https://github.com/QuanDo2000/dotfiles.git"

# Logging helpers
function Info($msg) { if (-not $script:Quiet) { Write-Host "  [ .. ] $msg" } }
function Success($msg) { if (-not $script:Quiet) { Write-Host "  [ OK ] $msg" -ForegroundColor Green } }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }

# File helpers
function CopyWithBackup($source, $destination) {
    Info "Copying $source to $destination"
    if ($script:Dry) { return }

    if (Test-Path $destination) {
        if (-not $script:Force) {
            $diff = Compare-Object (Get-Content $source) (Get-Content $destination) -ErrorAction SilentlyContinue
            if (-not $diff) {
                Success "Skipped $source (already up to date)"
                return
            }
        }
        Copy-Item -Path $destination -Destination "$destination.bak" -Force
    }
    Copy-Item -Path $source -Destination $destination -Force
    Success "Copied $source to $destination"
}

function CopyDirWithBackup($source, $destination) {
    Info "Copying $source to $destination"
    if ($script:Dry) { return }

    if (Test-Path $destination) {
        if (-not $script:Force) {
            Copy-Item -Path $destination -Destination "$destination.bak" -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }
    Copy-Item -Path $source -Destination $destination -Force -Recurse
    Success "Copied $source to $destination"
}

function LinkFile($source, $destination) {
    Info "Linking $source to $destination"
    if ($script:Dry) { return }

    if (Test-Path $destination) {
        $current = (Get-Item $destination -ErrorAction SilentlyContinue)
        if ($current.Target -eq $source) {
            Success "Skipped $source (already linked)"
            return
        }
        if ($script:Force) {
            Remove-Item $destination -Force
        } else {
            Fail "File already exists: $destination. Use -Force to overwrite."
        }
    }
    New-Item -ItemType SymbolicLink -Path $destination -Target $source | Out-Null
    Success "Linked $source to $destination"
}

# Ensure repo exists
function EnsureRepo {
    if (-not (Test-Path $script:DotfilesDir)) {
        Info "Cloning dotfiles repo..."
        git clone $script:RepoUrl $script:DotfilesDir
        if ($LASTEXITCODE -ne 0) { Fail "Failed to clone dotfiles repo" }
    }
}

function UpdateRepo {
    Info "Updating dotfiles repo..."
    if (-not $script:Dry) {
        Push-Location $script:DotfilesDir
        git pull --rebase --autostash
        if ($LASTEXITCODE -ne 0) { Pop-Location; Fail "Failed to pull dotfiles repo" }
        Pop-Location
    }
    Success "Finished updating repo"
}

function InstallPackages {
    Info "Installing packages..."
    if ($script:Dry) { return }

    winget install Microsoft.Powershell Git.Git Microsoft.WindowsTerminal JanDeDobbeleer.OhMyPosh Neovim.Neovim JesseDuffield.lazygit BurntSushi.ripgrep.MSVC sharkdp.fd JernejSimoncic.Wget fzf --disable-interactivity --accept-package-agreements

    Install-Module -Name PowerShellGet -Force
    Install-Module PSReadLine -AllowPrerelease -Force
    Install-Module -Name Terminal-Icons -Repository PSGallery
    Update-Module

    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if (-not $scoopExists) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }

    scoop install mingw gcc main/ast-grep

    Success "Finished installing packages"
}

function InstallFont {
    Info "Installing FiraCode using scoop..."
    if ($script:Dry) { return }

    scoop bucket add nerd-fonts
    scoop install FiraCode
    scoop update FiraCode

    Success "Finished installing font"
}

function InstallExtras {
    InstallFont
}

function SetupSymlinks {
    Info "Setting up symlinks..."
    $configPath = Join-Path $script:DotfilesDir "windows"
    $sharedPath = Join-Path $script:DotfilesDir "shared"

    # PowerShell profiles
    $targets = @(
        "$HOME\Documents\WindowsPowerShell"
        "$HOME\Documents\PowerShell"
    )
    foreach ($target in $targets) {
        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target | Out-Null
        }
        CopyDirWithBackup -source "$configPath\Powershell\*" -destination $target
    }

    # Windows Terminal settings
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettingsSource = Join-Path $configPath "Terminal\settings.json"
    CopyWithBackup -source $terminalSettingsSource -destination $terminalSettingsPath

    # Vim settings
    CopyWithBackup -source (Join-Path $configPath "_gvimrc") -destination "$HOME\_gvimrc"
    CopyWithBackup -source (Join-Path $sharedPath ".vimrc") -destination "$HOME\_vimrc"
    CopyWithBackup -source (Join-Path $sharedPath ".gitconfig") -destination "$HOME\.gitconfig"

    # Neovim settings
    $nvimSettingsPath = "$env:LOCALAPPDATA\nvim"
    CopyDirWithBackup -source (Join-Path $sharedPath "config\nvim\*") -destination $nvimSettingsPath

    # Bin files (link to user PATH directory)
    $binSource = Join-Path $configPath "bin"
    if (Test-Path $binSource) {
        $binDest = "$HOME\.local\bin"
        if (-not (Test-Path $binDest)) {
            New-Item -ItemType Directory -Path $binDest | Out-Null
        }
        Get-ChildItem $binSource -File | ForEach-Object {
            LinkFile -source $_.FullName -destination (Join-Path $binDest $_.Name)
        }
    }

    Success "Finished setting up symlinks"
}

function SetupDotfiles {
    Info "Setting up dotfiles..."
    InstallPackages
    UpdateRepo
    InstallExtras
    SetupSymlinks
    Success "Done!"
}

function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  packages    Install system packages only
  extras      Install fonts
  symlinks    Create symlinks only

Options:
  -d, --dry     Dry run (no changes made)
  -f, --force   Overwrite existing files without prompting
  -q, --quiet   Only show errors
  -h, --help    Show this help message
"@
}

# Parse options
$command = "all"
$remaining = @()
foreach ($arg in $args) {
    switch ($arg) {
        { $_ -in "-d", "--dry" }   { $script:Dry = $true }
        { $_ -in "-f", "--force" } { $script:Force = $true }
        { $_ -in "-q", "--quiet" } { $script:Quiet = $true }
        { $_ -in "-h", "--help" }  { ShowUsage; exit 0 }
        default { $remaining += $arg }
    }
}
if ($remaining.Count -gt 0) { $command = $remaining[0] }

EnsureRepo

# Run command
switch ($command) {
    "all"      { SetupDotfiles }
    "packages" { InstallPackages }
    "extras"   { InstallExtras }
    "symlinks" { SetupSymlinks }
    default    { Fail "Unknown command: $command"; ShowUsage }
}
