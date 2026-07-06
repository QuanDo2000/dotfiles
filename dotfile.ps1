param(
    # When set, skip self-elevation and main dispatch so the script can be
    # dot-sourced by tests to load functions without side effects.
    [switch]$NoMain,
    # Flags declared explicitly so PowerShell's parameter binder doesn't
    # silently swallow `-d` as a prefix of the `-Debug` common parameter
    # (common parameters are auto-added because $RemainingArgs carries
    # [Parameter(...)]). Aliases preserve the short-form CLI.
    [Alias('d')][switch]$Dry,
    [Alias('f')][switch]$Force,
    [Alias('q')][switch]$Quiet,
    [Alias('h')][switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

# Self-elevate to admin (required for symlink creation)
if (-not $NoMain) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  [ .. ] Elevating to Administrator..."
        $pwsh = (Get-Process -Id $PID).Path
        # Flags were bound to named params, so re-emit them explicitly —
        # $RemainingArgs only contains the positional command now.
        $forwardedFlags = @()
        if ($Dry)   { $forwardedFlags += '-d' }
        if ($Force) { $forwardedFlags += '-f' }
        if ($Quiet) { $forwardedFlags += '-q' }
        if ($Help)  { $forwardedFlags += '-h' }
        $argList = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath) + $forwardedFlags + $RemainingArgs
        Start-Process -FilePath $pwsh -ArgumentList $argList -Verb RunAs -Wait
        exit $LASTEXITCODE
    }
}

# Global variables.
# Don't re-initialise $script:Dry/Quiet/Force here — at a script's top level,
# `$script:X` is the same variable as the param `$X`, so re-assigning would
# clobber values the binder just set from `-d`/`-f`/`-q` flags. Switch params
# already default to $false, which is all the reset was ever providing.
# Resolve symlink so invoking via ~\.local\bin points back to the real repo.
# Allow override via $env:DOTFILES_DIR so the install path is not hardcoded.
if ($env:DOTFILES_DIR -and (Test-Path $env:DOTFILES_DIR)) {
    $script:DotfilesDir = (Resolve-Path $env:DOTFILES_DIR).Path
} else {
    $scriptItem = Get-Item -LiteralPath $PSCommandPath
    $scriptReal = if ($scriptItem.Target) { $scriptItem.Target } else { $PSCommandPath }
    $script:DotfilesDir = (Resolve-Path (Split-Path $scriptReal -Parent)).Path
}
$script:RepoUrl = "https://github.com/QuanDo2000/dotfiles.git"

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
    $overwrite = $false
    $backup = $false
    if (Test-Path $destination) {
        $current = (Get-Item $destination -ErrorAction SilentlyContinue)
        if ($current.Target -eq $source) {
            $skip = $true
        } elseif (-not $script:OverwriteAll -and -not $script:BackupAll -and -not $script:SkipAll) {
            $action = PromptAction $destination (Split-Path $source -Leaf)
            switch ($action) {
                'o' { $overwrite = $true }
                'O' { $script:OverwriteAll = $true }
                'b' { $backup = $true }
                'B' { $script:BackupAll = $true }
                's' { $skip = $true }
                'S' { $script:SkipAll = $true }
                default { $skip = $true }
            }
        }

        if ($script:OverwriteAll -or $overwrite) {
            Remove-Item $destination -Force
            Success "Removed $destination"
        }
        if ($script:BackupAll -or $backup) {
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

function InstallPackages {
    Info "Installing packages..."
    if ($script:Dry) { return }

    $wingetPkgs = @(
        "Microsoft.Powershell", "Git.Git", "Microsoft.WindowsTerminal",
        "Neovim.Neovim", "Starship.Starship", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd",
        "junegunn.fzf", "Schniz.fnm", "jj-vcs.jj", "ajeetdsouza.zoxide"
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

    Success "Finished installing packages"
}

function InstallFont {
    Info "Installing FiraCode using scoop..."
    if ($script:Dry) { return }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    scoop bucket add nerd-fonts
    scoop install FiraCode

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
        FailSoft "fnm not found on PATH. Skipping Node.js LTS install — open a new shell and re-run 'dotfile.ps1'."
        return
    }

    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    fnm install --lts
    fnm use lts-latest
    fnm default lts-latest

    Success "Finished installing Node.js LTS"
}

function InstallExtras {
    InstallFont
    InstallFnm
}

function InstallCodex {
    param([switch]$Update)
    Info "Installing Codex CLI..."
    if ($script:Dry) { return }

    if ($Update -or -not (Get-Command codex -ErrorAction SilentlyContinue)) {
        $oldNonInteractive = $env:CODEX_NON_INTERACTIVE
        try {
            $env:CODEX_NON_INTERACTIVE = "1"
            Invoke-RestMethod https://chatgpt.com/codex/install.ps1 | Invoke-Expression
        } finally {
            if ($null -eq $oldNonInteractive) {
                Remove-Item Env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue
            } else {
                $env:CODEX_NON_INTERACTIVE = $oldNonInteractive
            }
        }
    } else {
        Info "Already installed Codex CLI"
    }

    Success "Finished installing Codex CLI"
}

# Install or update agent CLIs during package setup.
function InstallAi {
    param([switch]$Update)
    Info "Installing agent CLIs..."
    if ($script:Dry) { return }

    InstallCodex -Update:$Update

    if ($Update -and (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue)) {
        codebase-memory-mcp update
        if ($LASTEXITCODE -ne 0) { FailSoft "codebase-memory-mcp update failed with exit code $LASTEXITCODE" }
    } elseif (-not (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue)) {
        irm https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 | iex
    } else {
        Info "Already installed codebase-memory-mcp"
    }

    Success "Finished installing agent CLIs"
}

function Update-Packages {
    Info "Updating packages..."
    if ($script:Dry) { Success "Would run: winget upgrade --all" } else { winget upgrade --all --disable-interactivity --accept-package-agreements }
    InstallAi -Update
    Success "Finished updating packages"
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

function EnsureDir($dir) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function SetupSymlinks {
    Info "Setting up symlinks..."
    $script:OverwriteAll = $script:Force
    $script:BackupAll = $false
    $script:SkipAll = $false
    $configPath = Join-Path $script:DotfilesDir "config\windows"
    $sharedPath = Join-Path $script:DotfilesDir "config\shared"

    # Use $env:USERPROFILE rather than $HOME so test fixtures can override the
    # home directory by setting the env var. PowerShell's $HOME automatic
    # variable is read-only and frozen at session start, so $HOME would always
    # resolve to the real home — leaking test artifacts into ~/Documents etc.
    $userHome = $env:USERPROFILE

    # PowerShell profiles (link each file into the target dir).
    # Lowercase "documents" works on Windows (case-insensitive) and matches
    # the XDG-style lowercase convention on Unix/Mac when running PS tests.
    $psSource = Join-Path $configPath "Powershell"
    $targets = @(
        "$userHome\documents\WindowsPowerShell"
        "$userHome\documents\PowerShell"
    )
    foreach ($target in $targets) {
        EnsureDir $target
        Get-ChildItem $psSource -File | ForEach-Object {
            LinkFile -source $_.FullName -destination (Join-Path $target $_.Name)
        }
    }

    # Windows Terminal settings
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettingsSource = Join-Path $configPath "Terminal\settings.json"
    LinkFile -source $terminalSettingsSource -destination $terminalSettingsPath

    # Git config
    LinkFile -source (Join-Path $sharedPath ".gitconfig") -destination "$userHome\.gitconfig"
    LinkFile -source (Join-Path $configPath ".gitconfig") -destination "$userHome\.gitconfig.windows"

    # SSH config
    $sshDest = "$userHome\.ssh"
    EnsureDir $sshDest
    LinkFile -source (Join-Path $sharedPath ".ssh\config") -destination (Join-Path $sshDest "config")

    # Neovim settings (symlink the whole dir)
    $nvimSettingsPath = "$env:LOCALAPPDATA\nvim"
    LinkDir -source (Join-Path $sharedPath "config\nvim") -destination $nvimSettingsPath

    # Jujutsu config (lives at %APPDATA%\jj\config.toml on Windows)
    LinkDir -source (Join-Path $sharedPath "config\jj") -destination "$env:APPDATA\jj"

    # starship prompt config — shared with zsh, read from ~/.config/starship.toml.
    $starshipConfigDir = "$userHome\.config"
    EnsureDir $starshipConfigDir
    LinkFile -source (Join-Path $sharedPath "config\starship.toml") -destination (Join-Path $starshipConfigDir "starship.toml")

    # AI tool configs live in their own dotfolders (not ~/.config) alongside
    # runtime state we don't track, so link only the tracked files.
    $aiPath = Join-Path $sharedPath "ai"
    $aiLinks = @(
        @{ Src = "claude\settings.json";        Dst = "$userHome\.claude\settings.json" }
    )
    foreach ($link in $aiLinks) {
        $src = Join-Path $aiPath $link.Src
        if (-not (Test-Path $src)) { continue }
        $parent = Split-Path $link.Dst -Parent
        if (-not $script:Dry) { EnsureDir $parent }
        LinkFile -source $src -destination $link.Dst
    }

    # Link the repo-root dotfile.ps1 entry point into a user PATH directory.
    $dotfileSource = Join-Path $script:DotfilesDir "dotfile.ps1"
    if (Test-Path $dotfileSource) {
        $binDest = "$userHome\.local\bin"
        EnsureDir $binDest
        AddToUserPath $binDest
        LinkFile -source $dotfileSource -destination (Join-Path $binDest "dotfile.ps1")
    }

    Success "Finished setting up symlinks"
}

function Verify {
    $errors = 0

    Info "Verifying installed tools..."
    foreach ($cmd in @("git", "nvim", "fzf", "fd", "rg", "lazygit", "zoxide")) {
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
    foreach ($mod in @("PSReadLine")) {
        if (Get-Module -ListAvailable -Name $mod) {
            Success "PowerShell module: $mod"
        } else {
            FailSoft "PowerShell module missing: $mod"
            $errors++
        }
    }

    Info "Verifying copied files..."
    $sharedPath = Join-Path $script:DotfilesDir "config\shared"

    # Match SetupSymlinks: use $env:USERPROFILE so test fixtures can override.
    $userHome = $env:USERPROFILE
    $filesToCheck = @(
        @{ Source = (Join-Path $sharedPath ".gitconfig"); Dest = "$userHome\.gitconfig" }
        @{ Source = (Join-Path $sharedPath "config\starship.toml"); Dest = "$userHome\.config\starship.toml" }
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
    InstallAi
    SetupSymlinks
    Success "Done!"
}

function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update      Update system packages
  packages    Install system packages only
  verify      Verify installation

Options:
  -d, --dry     Dry run (no changes made)
  -f, --force   Overwrite existing files without prompting
  -q, --quiet   Only show errors
  -h, --help    Show this help message
"@
}

# Parse options. Extracted into a function so tests can drive it with
# synthetic argument arrays without executing the main dispatch below.
function ParseArgs([string[]]$Arguments) {
    $command = "all"
    $positional = @()
    foreach ($arg in $Arguments) {
        switch ($arg) {
            { $_ -in "-d", "--dry" }   { $script:Dry = $true }
            { $_ -in "-f", "--force" } { $script:Force = $true }
            { $_ -in "-q", "--quiet" } { $script:Quiet = $true }
            { $_ -in "-h", "--help" }  { ShowUsage; return '__help__' }
            default { $positional += $arg }
        }
    }
    if ($positional.Count -gt 0) { $command = $positional[0] }
    return $command
}

if (-not $NoMain) {
    # Flag params are already bound to $script:Dry/Force/Quiet at top level
    # (script and local scopes coincide here). Just handle -Help before
    # ParseArgs and let ParseArgs handle any flags still in $RemainingArgs
    # (e.g. from tests that drive it with synthetic arrays).
    if ($Help) { ShowUsage; exit 0 }

    $command = ParseArgs $RemainingArgs
    if ($command -eq '__help__') { exit 0 }

    EnsureRepo

    switch ($command) {
        "all"       { SetupDotfiles }
        "update"    { Update-Packages }
        "packages"  { InstallPackages }
        "verify"    { Verify }
        default     { Fail "Unknown command: $command"; ShowUsage }
    }
}
