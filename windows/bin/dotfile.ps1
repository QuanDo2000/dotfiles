$ErrorActionPreference = "Stop"

# Self-elevate to admin (required for symlink creation)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [ .. ] Elevating to Administrator..."
    $pwsh = (Get-Process -Id $PID).Path
    $argList = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath) + $args
    Start-Process -FilePath $pwsh -ArgumentList $argList -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# Global variables
$script:Dry = $false
$script:Quiet = $false
$script:Force = $false
# Resolve symlink so invoking via ~\.local\bin points back to the real repo.
# Allow override via $env:DOTFILES_DIR so the install path is not hardcoded.
if ($env:DOTFILES_DIR -and (Test-Path $env:DOTFILES_DIR)) {
    $script:DotfilesDir = (Resolve-Path $env:DOTFILES_DIR).Path
} else {
    $scriptItem = Get-Item -LiteralPath $PSCommandPath
    $scriptReal = if ($scriptItem.Target) { $scriptItem.Target } else { $PSCommandPath }
    $script:DotfilesDir = (Resolve-Path (Join-Path (Split-Path $scriptReal -Parent) "..\..")).Path
}
$script:RepoUrl = "https://github.com/QuanDo2000/dotfiles.git"

# Invoke-RestMethod with retry + exponential backoff. GitHub API is rate-limited
# to 60 req/hr unauthenticated; a single blip shouldn't kill the install.
function InvokeRestMethodRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers = @{ "User-Agent" = "dotfile.ps1" },
        [int]$MaxAttempts = 4
    )
    $delay = 2
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Headers $Headers
        } catch {
            if ($i -eq $MaxAttempts) { throw }
            Info "Request to $Uri failed (attempt $i/$MaxAttempts): $($_.Exception.Message). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
            $delay *= 2
        }
    }
}

# Logging helpers
function Info($msg) { if (-not $script:Quiet) { Write-Host "  [ .. ] $msg" } }
function Success($msg) { if (-not $script:Quiet) { Write-Host "  [ OK ] $msg" -ForegroundColor Green } }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }
function FailSoft($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# File helpers
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

function LinkDir($source, $destination) {
    Info "Linking directory $source to $destination"
    if ($script:Dry) { return }

    if (Test-Path $destination) {
        $current = Get-Item $destination -ErrorAction SilentlyContinue
        if ($current.Target -eq $source) {
            Success "Skipped $destination (already linked)"
            return
        }
        if ($script:Force) {
            if ($current.PSIsContainer -and -not $current.LinkType) {
                Remove-Item $destination -Recurse -Force
            } else {
                Remove-Item $destination -Force
            }
        } else {
            Move-Item $destination "$destination.bak" -Force
            Success "Moved $destination to $destination.bak"
        }
    }

    $parent = Split-Path $destination -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
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

function WingetHas($id) {
    $null = winget list --id $id --exact --accept-source-agreements 2>$null | Out-String
    return ($LASTEXITCODE -eq 0)
}

function ScoopHas($name) {
    $bare = ($name -split '/')[-1]
    return [Boolean](scoop list $bare 6>$null | Where-Object { $_.Name -eq $bare })
}

function InstallPackages {
    Info "Installing packages..."
    if ($script:Dry) { return }

    $wingetPkgs = @(
        "Microsoft.Powershell", "Git.Git", "Microsoft.WindowsTerminal",
        "JanDeDobbeleer.OhMyPosh", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd", "JernejSimoncic.Wget",
        "junegunn.fzf", "Schniz.fnm"
    )
    Info "Checking winget packages ($($wingetPkgs.Count) total)..."
    $missing = @()
    for ($i = 0; $i -lt $wingetPkgs.Count; $i++) {
        $pkg = $wingetPkgs[$i]
        Info "  [$($i + 1)/$($wingetPkgs.Count)] Checking $pkg..."
        if (-not (WingetHas $pkg)) { $missing += $pkg }
    }
    if ($missing.Count -gt 0) {
        Info "Installing $($missing.Count) missing winget package(s): $($missing -join ', ')"
        winget install @missing --disable-interactivity --accept-package-agreements
    } else {
        Success "All winget packages already installed"
    }

    Info "Upgrading all winget packages..."
    winget upgrade --all --disable-interactivity --accept-package-agreements

    InstallNeovimNightly

    # Run module installs in a fresh pwsh process to avoid
    # "module is currently in use" warnings from PackageManagement/PowerShellGet.
    $modules = @("PowerShellGet", "PSReadLine", "Terminal-Icons")
    Info "Checking PowerShell modules..."
    $missingMods = @($modules | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if ($missingMods.Count -gt 0) {
        Info "Installing missing PowerShell modules: $($missingMods -join ', ') (this may take a few minutes)"
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
        if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
        $moduleScript = @'
$ErrorActionPreference = "Stop"
Install-Module -Name PowerShellGet -Force -AllowClobber -Scope CurrentUser
Install-Module PSReadLine -AllowPrerelease -Force -Scope CurrentUser
Install-Module -Name Terminal-Icons -Repository PSGallery -Force -Scope CurrentUser
Update-Module
'@
        & $pwsh -NoProfile -ExecutionPolicy Bypass -Command $moduleScript
        if ($LASTEXITCODE -ne 0) { FailSoft "Module install subprocess exited with code $LASTEXITCODE" }
    } else {
        Success "All PowerShell modules already installed"
    }

    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if (-not $scoopExists) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }

    $scoopPkgs = @("mingw", "gcc", "extras/vcredist2022", "zig", "main/ast-grep")
    scoop bucket add extras *> $null
    Info "Checking scoop packages..."
    $missingScoop = @($scoopPkgs | Where-Object { -not (ScoopHas $_) })
    if ($missingScoop.Count -gt 0) {
        Info "Installing missing scoop package(s): $($missingScoop -join ', ')"
        scoop install @missingScoop
    } else {
        Success "All scoop packages already installed"
    }

    Info "Updating all scoop packages..."
    scoop update *

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

function InstallFnm {
    Info "Installing Node.js LTS via fnm..."
    if ($script:Dry) { return }

    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"
    }
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        FailSoft "fnm not found on PATH. Skipping Node.js LTS install — open a new shell and re-run 'dotfile.ps1 extras'."
        return
    }

    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    fnm install --lts
    fnm use lts-latest
    fnm default lts-latest

    Success "Finished installing Node.js LTS"
}

function InstallTreeSitter {
    Info "Installing tree-sitter CLI via npm..."
    if ($script:Dry) { return }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        FailSoft "npm not found on PATH. Skipping tree-sitter CLI install — open a new shell and re-run 'dotfile.ps1 extras'."
        return
    }

    npm install -g tree-sitter-cli
    if ($LASTEXITCODE -ne 0) {
        FailSoft "npm install -g tree-sitter-cli failed with exit code $LASTEXITCODE"
        return
    }

    Success "Finished installing tree-sitter CLI"
}

function InstallExtras {
    InstallFont
    InstallFnm
    InstallTreeSitter
}

function InstallNeovimNightly {
    Info "Checking Neovim nightly..."
    if ($script:Dry) { return }

    $installDir = Join-Path $env:LOCALAPPDATA "Programs\Neovim"
    $binDir = Join-Path $installDir "bin"
    $markerFile = Join-Path $installDir ".nightly-sha"

    try {
        $release = InvokeRestMethodRetry -Uri "https://api.github.com/repos/neovim/neovim/releases/tags/nightly"
    } catch {
        FailSoft "Could not query Neovim nightly release after retries: $($_.Exception.Message)"
        return
    }

    $latestSha = $release.target_commitish
    $asset = $release.assets | Where-Object { $_.name -eq "nvim-win64.zip" } | Select-Object -First 1
    if (-not $asset) {
        FailSoft "nvim-win64.zip not found in nightly release assets"
        return
    }

    $currentSha = if (Test-Path $markerFile) { (Get-Content -Raw $markerFile).Trim() } else { "" }
    if ($currentSha -eq $latestSha -and (Test-Path (Join-Path $binDir "nvim.exe"))) {
        Success "Neovim nightly up to date ($($latestSha.Substring(0, 7)))"
        AddToUserPath $binDir
        return
    }

    Info "Downloading Neovim nightly ($($latestSha.Substring(0, 7)))..."
    $tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) "nvim-nightly-$([Guid]::NewGuid().ToString('N')).zip"
    $tmpExtract = Join-Path ([System.IO.Path]::GetTempPath()) "nvim-nightly-$([Guid]::NewGuid().ToString('N'))"
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing
        Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

        $extracted = Get-ChildItem -Path $tmpExtract -Directory | Select-Object -First 1
        if (-not $extracted) { Fail "Extracted nightly archive has no top-level directory" }

        if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Get-ChildItem -Path $extracted.FullName -Force | Move-Item -Destination $installDir
        Set-Content -Path $markerFile -Value $latestSha -NoNewline
        Success "Installed Neovim nightly to $installDir"
    } finally {
        if (Test-Path $tmpZip) { Remove-Item -Force $tmpZip }
        if (Test-Path $tmpExtract) { Remove-Item -Recurse -Force $tmpExtract }
    }

    AddToUserPath $binDir
}

function AddToUserPath($dir) {
    Info "Ensuring $dir is on user PATH"
    if ($script:Dry) { return }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @()
    if ($userPath) { $entries = $userPath.Split(';') | Where-Object { $_ -ne "" } }
    if ($entries -contains $dir) {
        Success "$dir already on user PATH"
    } else {
        $newPath = (($entries + $dir) -join ';')
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Success "Added $dir to user PATH"
    }

    if (-not ($env:Path.Split(';') -contains $dir)) {
        $env:Path = "$env:Path;$dir"
    }
}

function SetupSymlinks {
    Info "Setting up symlinks..."
    $script:OverwriteAll = $script:Force
    $script:BackupAll = $false
    $script:SkipAll = $false
    $configPath = Join-Path $script:DotfilesDir "windows"
    $sharedPath = Join-Path $script:DotfilesDir "shared"

    # PowerShell profiles (link each file into the target dir)
    $psSource = Join-Path $configPath "Powershell"
    $targets = @(
        "$HOME\Documents\WindowsPowerShell"
        "$HOME\Documents\PowerShell"
    )
    foreach ($target in $targets) {
        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target | Out-Null
        }
        Get-ChildItem $psSource -File | ForEach-Object {
            LinkFile -source $_.FullName -destination (Join-Path $target $_.Name)
        }
    }

    # Windows Terminal settings
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettingsSource = Join-Path $configPath "Terminal\settings.json"
    LinkFile -source $terminalSettingsSource -destination $terminalSettingsPath

    # Vim settings
    LinkFile -source (Join-Path $configPath "_gvimrc") -destination "$HOME\_gvimrc"
    LinkFile -source (Join-Path $sharedPath ".vimrc") -destination "$HOME\_vimrc"
    LinkFile -source (Join-Path $sharedPath ".gitconfig") -destination "$HOME\.gitconfig"
    LinkFile -source (Join-Path $configPath ".gitconfig") -destination "$HOME\.gitconfig.windows"

    # SSH config
    $sshDest = "$HOME\.ssh"
    if (-not (Test-Path $sshDest)) {
        New-Item -ItemType Directory -Path $sshDest | Out-Null
    }
    LinkFile -source (Join-Path $configPath ".ssh\config") -destination (Join-Path $sshDest "config")

    # Neovim settings (symlink the whole dir)
    $nvimSettingsPath = "$env:LOCALAPPDATA\nvim"
    LinkDir -source (Join-Path $sharedPath "config\nvim") -destination $nvimSettingsPath

    # Bin files (link to user PATH directory)
    $binSource = Join-Path $configPath "bin"
    if (Test-Path $binSource) {
        $binDest = "$HOME\.local\bin"
        if (-not (Test-Path $binDest)) {
            New-Item -ItemType Directory -Path $binDest | Out-Null
        }
        AddToUserPath $binDest
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
