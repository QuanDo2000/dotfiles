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
function FailSoft($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

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

function PromptAction($destination, $sourceName) {
    Write-Host "  [ ?? ] File already exists: $destination ($sourceName)"
    Write-Host "         [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all"
    $key = [System.Console]::ReadKey($true).KeyChar
    return $key
}

function LinkFile($source, $destination) {
    Info "Linking $source to $destination"
    if ($script:Dry) { return }

    $skip = $false
    if (Test-Path $destination) {
        $current = (Get-Item $destination -ErrorAction SilentlyContinue)
        if ($current.Target -eq $source) {
            $skip = $true
        } elseif (-not $script:OverwriteAll -and -not $script:BackupAll -and -not $script:SkipAll) {
            $action = PromptAction $destination (Split-Path $source -Leaf)
            switch ($action) {
                'o' { $script:Force = $false }
                'O' { $script:OverwriteAll = $true }
                'b' { }
                'B' { $script:BackupAll = $true }
                's' { $skip = $true }
                'S' { $script:SkipAll = $true }
            }
        }

        if ($script:OverwriteAll -or $action -eq 'o') {
            Remove-Item $destination -Force
            Success "Removed $destination"
        }
        if ($script:BackupAll -or $action -eq 'b') {
            Move-Item $destination "$destination.bak" -Force
            Success "Moved $destination to $destination.bak"
        }
        if ($script:SkipAll -or $skip) {
            Success "Skipped $source"
            return
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
    $script:OverwriteAll = $script:Force
    $script:BackupAll = $false
    $script:SkipAll = $false
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

function Verify {
    $errors = 0

    Info "Verifying installed tools..."
    foreach ($cmd in @("git", "nvim", "fzf", "fd", "rg", "lazygit")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            Success "$cmd found: $($found.Source)"
        } else {
            FailSoft "$cmd not found"
            $errors++
        }
    }

    Info "Verifying scoop packages..."
    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if ($scoopExists) {
        Success "scoop installed"
    } else {
        FailSoft "scoop not installed"
        $errors++
    }

    Info "Verifying PowerShell modules..."
    foreach ($mod in @("PSReadLine", "Terminal-Icons")) {
        if (Get-Module -ListAvailable -Name $mod) {
            Success "PowerShell module: $mod"
        } else {
            FailSoft "PowerShell module missing: $mod"
            $errors++
        }
    }

    Info "Verifying copied files..."
    $configPath = Join-Path $script:DotfilesDir "windows"
    $sharedPath = Join-Path $script:DotfilesDir "shared"

    $filesToCheck = @(
        @{ Source = (Join-Path $sharedPath ".gitconfig"); Dest = "$HOME\.gitconfig" }
        @{ Source = (Join-Path $sharedPath ".vimrc"); Dest = "$HOME\_vimrc" }
        @{ Source = (Join-Path $configPath "_gvimrc"); Dest = "$HOME\_gvimrc" }
    )
    foreach ($file in $filesToCheck) {
        if (Test-Path $file.Dest) {
            $diff = Compare-Object (Get-Content $file.Source) (Get-Content $file.Dest) -ErrorAction SilentlyContinue
            if (-not $diff) {
                Success "$($file.Dest) matches source"
            } else {
                Info "$($file.Dest) exists but differs from source"
            }
        } else {
            FailSoft "$($file.Dest) not found"
            $errors++
        }
    }

    Info "Verifying neovim config..."
    $nvimPath = "$env:LOCALAPPDATA\nvim"
    if (Test-Path (Join-Path $nvimPath "init.lua")) {
        Success "Neovim config installed"
    } else {
        FailSoft "Neovim config not found at $nvimPath"
        $errors++
    }

    Write-Host ""
    if ($errors -eq 0) {
        Success "All checks passed!"
    } else {
        Info "$errors issue(s) found"
    }
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
  verify      Verify installation

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
    "verify"   { Verify }
    default    { Fail "Unknown command: $command"; ShowUsage }
}
