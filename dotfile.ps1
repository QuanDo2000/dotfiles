param(
    # When set, skip main dispatch so the script can be
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

function Resolve-DotfilesDir($Override, $ScriptPath) {
    if ($Override) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Override)
    }
    $scriptItem = Get-Item -LiteralPath $ScriptPath
    $scriptReal = if ($scriptItem.Target) { $scriptItem.Target } else { $ScriptPath }
    return (Resolve-Path (Split-Path $scriptReal -Parent)).Path
}

# Global variables.
# Don't re-initialise $script:Dry/Quiet/Force here — at a script's top level,
# `$script:X` is the same variable as the param `$X`, so re-assigning would
# clobber values the binder just set from `-d`/`-f`/`-q` flags. Switch params
# already default to $false, which is all the reset was ever providing.
# Resolve symlink so invoking via ~\.local\bin points back to the real repo.
# Allow override via $env:DOTFILES_DIR so the install path is not hardcoded.
$script:DotfilesDir = Resolve-DotfilesDir $env:DOTFILES_DIR $PSCommandPath
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

function Get-LinkConflict($source, $destination) {
    if (-not (Test-Path $destination)) { return $null }

    $current = Get-Item $destination -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Item = $current
        AlreadyLinked = ($current.Target -eq $source)
    }
}

function Invoke-ElevatedSymlink($source, $destination) {
    $escapedSource = $source.Replace("'", "''")
    $escapedDestination = $destination.Replace("'", "''")
    $command = "New-Item -ItemType SymbolicLink -Path '$escapedDestination' -Target '$escapedSource' | Out-Null"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @("-NoProfile", "-EncodedCommand", $encoded) -Verb RunAs -Wait -PassThru
    if ($elevated.ExitCode -ne 0) { throw "Elevated symlink creation failed: $destination" }
}

function Test-SymlinkPrivilegeError($exception) {
    while ($exception) {
        if ($exception -is [System.UnauthorizedAccessException] -or
            $exception.NativeErrorCode -eq 1314 -or
            $exception.HResult -eq -2147023582 -or
            $exception.Message -match 'required privilege') {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function New-Symlink($source, $destination) {
    $parent = Split-Path $destination -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    try {
        New-Item -ItemType SymbolicLink -Path $destination -Target $source | Out-Null
    } catch {
        if ($NoMain -or -not (Test-SymlinkPrivilegeError $_.Exception)) { throw }
        Invoke-ElevatedSymlink $source $destination
    }
}

function LinkPath($source, $destination, [bool]$isDirectory = $false) {
    Info "Linking $(if ($isDirectory) { 'directory ' })$source to $destination"
    if ($script:Dry) { return }

    $skip = $false
    $overwrite = $false
    $backup = $false
    $conflict = Get-LinkConflict $source $destination
    if ($conflict) {
        if ($conflict.AlreadyLinked) {
            Success "Skipped $destination (already linked)"
            return
        }

        if ($isDirectory) {
            $overwrite = $script:Force
            $backup = -not $script:Force
        } elseif (-not $script:OverwriteAll -and -not $script:BackupAll -and -not $script:SkipAll) {
            switch (PromptAction $destination (Split-Path $source -Leaf)) {
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
            $recurse = $conflict.Item.PSIsContainer -and -not $conflict.Item.LinkType
            Remove-Item $destination -Force -Recurse:$recurse
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

    New-Symlink $source $destination
    Success "Linked $source to $destination"
}

function Invoke-Winget($FailureMessage, [string[]]$Arguments) {
    Invoke-NativeChecked $FailureMessage {
        winget @Arguments --disable-interactivity --accept-package-agreements --accept-source-agreements
    }
}

# Ensure repo exists
function EnsureRepo {
    if (-not (Test-Path (Join-Path $script:DotfilesDir 'dotfile.ps1'))) {
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

function Get-WingetPackages {
    @(
        "Microsoft.PowerShell", "Git.Git", "GnuPG.Gpg4win", "Microsoft.WindowsTerminal",
        "Neovim.Neovim", "Starship.Starship", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd", "junegunn.fzf",
        "Schniz.fnm", "jj-vcs.jj", "ajeetdsouza.zoxide",
        "Python.Python.3.14", "GitHub.cli"
    )
}

function Get-ScoopPackages {
    @("FiraCode", "jq", "ast-grep")
}

function Get-RequiredCommands {
    @(
        "git", "gpg", "nvim", "starship", "fzf", "fd", "rg", "lazygit",
        "fnm", "node", "jj", "zoxide", "jq", "ast-grep", "codex", "pi",
        "codebase-memory-mcp", "py", "gh"
    )
}

function Invoke-NativeChecked($FailureMessage, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function InstallPackages {
    Info "Installing packages..."
    if ($script:Dry) { return }

    $wingetPkgs = @(Get-WingetPackages)
    Info "Checking winget packages ($($wingetPkgs.Count) total)..."
    $missing = @()
    for ($i = 0; $i -lt $wingetPkgs.Count; $i++) {
        $pkg = $wingetPkgs[$i]
        Info "  [$($i + 1)/$($wingetPkgs.Count)] Checking $pkg..."
        if (-not (WingetHas $pkg)) { $missing += $pkg }
    }
    if ($missing.Count -gt 0) {
        Info "Installing $($missing.Count) missing winget package(s): $($missing -join ', ')"
        foreach ($pkg in $missing) {
            Invoke-Winget "winget install $pkg failed" @('install', '--id', $pkg, '--exact')
        }
    } else {
        Success "All winget packages already installed"
    }

    Info "Upgrading all winget packages..."
    Invoke-Winget "winget upgrade failed" @('upgrade', '--all')

    Success "Finished installing packages"
}

function InstallScoopPackages {
    param([switch]$Update)
    Info "Installing Scoop packages..."
    if ($script:Dry) { return }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
    $buckets = scoop bucket list
    if ($LASTEXITCODE -ne 0) { throw "scoop bucket list failed" }
    if ($buckets.Name -notcontains "nerd-fonts") {
        Invoke-NativeChecked "scoop bucket add nerd-fonts failed" { scoop bucket add nerd-fonts }
    }

    $installed = @(scoop list)
    if ($LASTEXITCODE -ne 0) { throw "scoop list failed" }
    foreach ($package in Get-ScoopPackages) {
        if ($installed.Name -notcontains $package) {
            Invoke-NativeChecked "scoop install $package failed" { scoop install $package }
        }
    }
    if ($Update) {
        Invoke-NativeChecked "scoop update failed" { scoop update }
        $packages = @(Get-ScoopPackages)
        Invoke-NativeChecked "scoop package update failed" { scoop update @packages }
    }

    Success "Finished installing Scoop packages"
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function InstallFnm {
    Info "Installing Node.js LTS via fnm..."
    if ($script:Dry) { return }

    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        Refresh-ProcessPath
    }
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        FailSoft "fnm not found on PATH. Skipping Node.js LTS install — open a new shell and re-run 'dotfile.ps1'."
        return
    }

    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    Invoke-NativeChecked "fnm install --lts failed" { fnm install --lts }
    Invoke-NativeChecked "fnm use lts-latest failed" { fnm use lts-latest }
    Invoke-NativeChecked "fnm default lts-latest failed" { fnm default lts-latest }

    Success "Finished installing Node.js LTS"
}

function InstallExtras {
    param([switch]$Update)
    InstallScoopPackages -Update:$Update
    InstallFnm
}

function InstallManagedPackages {
    InstallPackages
    InstallExtras
    InstallAi
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
    Refresh-ProcessPath
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        throw "codex command not found after installation"
    }

    Success "Finished installing Codex CLI"
}

function SyncCodexConfig {
    $source = Join-Path $script:DotfilesDir 'config\windows\ai\codex\config.toml'
    $target = Join-Path $env:USERPROFILE '.codex\config.toml'
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $source -Destination $target
    } else {
        $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { '' } else { $source }
        Invoke-NativeChecked 'Codex config seed comparison failed' {
            py -3.14 (Join-Path $script:DotfilesDir 'scripts\seed_merge\codex.py') $target $source $applySeed
        }
    }
    (Get-Item -LiteralPath $target).IsReadOnly = $false
}

function InstallPi {
    param([switch]$Update)
    Info "Installing Pi coding agent..."
    if ($script:Dry) { return }

    if ($Update -or -not (Get-Command pi -ErrorAction SilentlyContinue)) {
        Invoke-NativeChecked "Pi install failed" {
            npm install --global @earendil-works/pi-coding-agent
        }
    } else {
        Info "Already installed Pi coding agent"
    }
    Refresh-ProcessPath
    if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
        throw "pi command not found after installation"
    }
    Success "Finished installing Pi coding agent"
}

function SyncPiConfigs {
    Info "Syncing Pi configuration..."
    if ($script:Dry) { return }

    $seedDir = Join-Path $script:DotfilesDir "config\shared\ai\pi"
    $targetDir = Join-Path $env:USERPROFILE ".pi\agent"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    foreach ($name in @("settings.json", "mcp.json")) {
        $source = Join-Path $seedDir $name
        $target = Join-Path $targetDir $name
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $source -Destination $target
            continue
        }

        $python = Get-Command py -ErrorAction SilentlyContinue
        $jq = Get-Command jq -ErrorAction SilentlyContinue
        if (-not $python -or -not $jq) {
            throw "py and jq are required to sync Pi configuration"
        }

        $mergeScript = Join-Path $script:DotfilesDir "scripts\seed_merge\pi.py"
        $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { "" } else { $source }
        Invoke-NativeChecked "Pi $name seed comparison failed" {
            py -3.14 $mergeScript $target $source $applySeed
        }
        $mergeSource = if ($applySeed) { $applySeed } else { $source }
        $merged = & jq -s '.[0] * .[1]' $target $mergeSource
        if ($LASTEXITCODE -ne 0) { throw "Pi $name merge failed" }
        Set-Content -LiteralPath $target -Value ($merged -join "`n") -Encoding utf8
    }

    $extensionDir = Join-Path $targetDir "extensions"
    New-Item -ItemType Directory -Force -Path $extensionDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $seedDir "codex-status.js") -Destination (Join-Path $extensionDir "codex-status.js") -Force
    Success "Finished syncing Pi configuration"
}

# Install or update agent CLIs during package setup.
function InstallAi {
    param([switch]$Update)
    Info "Installing agent CLIs..."
    if ($script:Dry) { return }

    InstallCodex -Update:$Update

    if ($Update -and (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue)) {
        Invoke-NativeChecked "codebase-memory-mcp update failed" { codebase-memory-mcp update }
    } elseif (-not (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue)) {
        irm https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 | iex
    } else {
        Info "Already installed codebase-memory-mcp"
    }
    Refresh-ProcessPath
    if (-not (Get-Command codebase-memory-mcp -ErrorAction SilentlyContinue)) {
        throw "codebase-memory-mcp command not found after installation"
    }

    SyncCodexConfig
    InstallPi -Update:$Update
    SyncPiConfigs

    Success "Finished installing agent CLIs"
}

function Get-NeovimCommand {
    $command = Get-Command nvim -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $wingetLink = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nvim.exe"
    if (Test-Path -LiteralPath $wingetLink) { return $wingetLink }

    $programFiles = Join-Path $env:ProgramFiles "Neovim\bin\nvim.exe"
    if (Test-Path -LiteralPath $programFiles) { return $programFiles }

    $wingetPackages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    $installed = Get-ChildItem -Path $wingetPackages -Filter nvim.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installed) { return $installed.FullName }
    return $null
}

function Get-NeovimDataPath($nvim) {
    $output = & $nvim --headless --clean "+lua io.write(vim.fn.stdpath('data'))" "+qa" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($output -join '').Trim())
}

function Sync-LazyVim {
    Info "Installing or updating LazyVim..."
    if ($script:Dry) { return }

    try {
        $nvim = Get-NeovimCommand
        if (-not $nvim) { throw "nvim executable not found" }
        & $nvim --headless "+Lazy! sync" "+qa" 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "LazyVim sync failed; Neovim may finish setup on first start"
        } else {
            $dataPath = Get-NeovimDataPath $nvim
            if (-not $dataPath) { throw "could not determine Neovim data path" }
            $lazyRoot = Join-Path $dataPath "lazy"
            if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot "lazy.nvim")) -or
                -not (Test-Path -LiteralPath (Join-Path $lazyRoot "LazyVim"))) {
                Write-Warning "LazyVim sync did not install lazy.nvim and LazyVim; Neovim may finish setup on first start"
            }
        }
    } catch {
        Write-Warning "LazyVim sync failed; Neovim may finish setup on first start: $_"
    }
}

function Invoke-UpdatedPackageInstall($DotfileScript, [bool]$DryRun, [bool]$ForceRun, [bool]$QuietRun) {
    & {
        param($ScriptPath, $IsDry, $IsForce, $IsQuiet)
        . $ScriptPath -NoMain -Dry:$IsDry -Force:$IsForce -Quiet:$IsQuiet
        $script:Dry = $IsDry
        $script:Force = $IsForce
        $script:Quiet = $IsQuiet
        InstallPackages
        InstallExtras -Update
        InstallAi -Update
        Sync-LazyVimConfig
        Sync-LazyVim
        if (-not $script:Dry) { Assert-WindowsHealthy }
    } $DotfileScript $DryRun $ForceRun $QuietRun
}

function Update-Packages {
    Info "Updating packages..."
    UpdateRepo
    Invoke-UpdatedPackageInstall (Join-Path $script:DotfilesDir 'dotfile.ps1') $script:Dry $script:Force $script:Quiet
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

function New-LinkSpec($Kind, $Source, $Destination, [bool]$Verify = $false, [bool]$AddToPath = $false) {
    [pscustomobject]@{
        Kind = $Kind
        Source = $Source
        Destination = $Destination
        Verify = $Verify
        AddToPath = $AddToPath
    }
}

function Get-WindowsLinkSpecs {
    $configPath = Join-Path $script:DotfilesDir "config\windows"
    $sharedPath = Join-Path $script:DotfilesDir "config\shared"

    # Use $env:USERPROFILE rather than $HOME so test fixtures can override the
    # home directory by setting the env var. PowerShell's $HOME automatic
    # variable is read-only and frozen at session start, so $HOME would always
    # resolve to the real home — leaking test artifacts into ~/Documents etc.
    $userHome = $env:USERPROFILE
    $specs = @()

    # PowerShell profiles (link each file into the target dir).
    $psSource = Join-Path $configPath "Powershell"
    $targets = @(
        "$userHome\Documents\WindowsPowerShell"
        "$userHome\Documents\PowerShell"
    )
    if (Test-Path $psSource) {
        foreach ($target in $targets) {
            Get-ChildItem $psSource -File | ForEach-Object {
                $specs += New-LinkSpec 'File' $_.FullName (Join-Path $target $_.Name)
            }
        }
    }

    # Windows Terminal settings
    $specs += New-LinkSpec 'File' `
        (Join-Path $configPath "Terminal\settings.json") `
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    # Git config
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".gitconfig") "$userHome\.gitconfig" $true
    $specs += New-LinkSpec 'File' (Join-Path $configPath ".gitconfig") "$userHome\.gitconfig.windows"

    # SSH config
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".ssh\config") "$userHome\.ssh\config" $true

    # Neovim settings: keep LazyVim's runtime-written lazyvim.json writable.
    $nvimSource = Join-Path $sharedPath "config\nvim"
    $nvimTarget = "$env:LOCALAPPDATA\nvim"
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "init.lua") (Join-Path $nvimTarget "init.lua")
    $specs += New-LinkSpec 'Dir' (Join-Path $nvimSource "lua") (Join-Path $nvimTarget "lua")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource ".gitignore") (Join-Path $nvimTarget ".gitignore")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "stylua.toml") (Join-Path $nvimTarget "stylua.toml")

    # Jujutsu config (lives at %APPDATA%\jj\config.toml on Windows)
    $specs += New-LinkSpec 'Dir' (Join-Path $sharedPath "config\jj") "$env:APPDATA\jj"

    # starship prompt config — shared with zsh, read from ~/.config/starship.toml.
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath "config\starship.toml") (Join-Path $userHome ".config\starship.toml") $true

    # AI tool configs live in their own dotfolders (not ~/.config) alongside
    # runtime state we don't track, so link only the tracked files.
    $claudeSettings = Join-Path $sharedPath "ai\claude\settings.json"
    if (Test-Path $claudeSettings) {
        $specs += New-LinkSpec 'File' $claudeSettings "$userHome\.claude\settings.json"
    }

    # Link the repo-root dotfile.ps1 entry point into a user PATH directory.
    $dotfileSource = Join-Path $script:DotfilesDir "dotfile.ps1"
    if (Test-Path $dotfileSource) {
        $binDest = "$userHome\.local\bin"
        $specs += New-LinkSpec 'File' $dotfileSource (Join-Path $binDest "dotfile.ps1") $false $true
    }

    return $specs
}

function Migrate-WindowsNvimConfig {
    if ($script:Dry) { return }
    $destination = "$env:LOCALAPPDATA\nvim"
    if (-not (Test-Path -LiteralPath $destination)) { return }

    $item = Get-Item -LiteralPath $destination -Force
    if (-not $item.LinkType) { return }

    $legacySource = Join-Path $script:DotfilesDir "config\shared\config\nvim"
    if ($item.Target -ne $legacySource) {
        throw "Neovim config points to unexpected target: $($item.Target)"
    }
    Remove-Item -LiteralPath $destination -Force
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
}

function Sync-LazyVimConfig {
    Info "Syncing writable LazyVim configuration..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir "config\shared\config\nvim\lazyvim.json"
    $target = "$env:LOCALAPPDATA\nvim\lazyvim.json"
    $base = "$env:LOCALAPPDATA\dotfiles\lazyvim-seed.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent), (Split-Path $base -Parent) | Out-Null

    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $source -Destination $target
        Copy-Item -LiteralPath $source -Destination $base
        return
    }

    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "py is required to sync LazyVim configuration"
    }
    $mergeScript = Join-Path $script:DotfilesDir "scripts\seed_merge\lazyvim.py"
    $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { "" } else { $source }
    Invoke-NativeChecked "LazyVim config seed merge failed" {
        py -3.14 $mergeScript $target $source $applySeed $base
    }
}

function SetupSymlinks {
    Info "Setting up symlinks..."
    $script:OverwriteAll = $script:Force
    $script:BackupAll = $false
    $script:SkipAll = $false
    Migrate-WindowsNvimConfig

    foreach ($spec in Get-WindowsLinkSpecs) {
        if ($spec.AddToPath) {
            AddToUserPath (Split-Path $spec.Destination -Parent)
        }
        LinkPath -source $spec.Source -destination $spec.Destination -isDirectory ($spec.Kind -eq 'Dir')
    }
    Sync-LazyVimConfig

    Success "Finished setting up symlinks"
}

function Verify {
    $errors = 0

    Info "Verifying installed tools..."
    foreach ($cmd in Get-RequiredCommands) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            Success "$cmd found: $($found.Source)"
        } else {
            FailSoft "$cmd not found"
            $errors++
        }
    }

    Info "Verifying Winget packages..."
    foreach ($id in Get-WingetPackages) {
        if (WingetHas $id) {
            Success "Winget package: $id"
        } else {
            FailSoft "Winget package missing: $id"
            $errors++
        }
    }

    Info "Verifying scoop packages..."
    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if ($scoopExists) {
        Success "scoop installed"
        $installedScoopPackages = @(scoop list)
        if ($LASTEXITCODE -ne 0) {
            FailSoft "scoop package list failed"
            $errors++
        } else {
            foreach ($name in Get-ScoopPackages) {
                if ($installedScoopPackages.Name -contains $name) {
                    Success "Scoop package: $name"
                } else {
                    FailSoft "Scoop package missing: $name"
                    $errors++
                }
            }
        }
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

    Info "Verifying managed links..."
    foreach ($file in Get-WindowsLinkSpecs) {
        if (-not (Test-Path -LiteralPath $file.Destination)) {
            FailSoft "$($file.Destination) not found"
            $errors++
            continue
        }
        $item = Get-Item -LiteralPath $file.Destination -Force
        if ($item.Target -eq $file.Source) {
            Success "$($file.Destination) -> $($file.Source)"
        } else {
            FailSoft "$($file.Destination) is not linked to $($file.Source)"
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

    Info "Verifying Codex config..."
    $codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $codexConfig)) {
        FailSoft "$codexConfig not found"
        $errors++
    } elseif (($item = Get-Item -LiteralPath $codexConfig -Force).PSIsContainer -or
        $item.LinkType -or $item.IsReadOnly) {
        FailSoft "$codexConfig must be a regular writable file"
        $errors++
    } else {
        Success "Codex config installed"
    }

    Write-Host ""
    if ($errors -eq 0) {
        $script:VerifyFailed = $false
        Success "All checks passed!"
    } else {
        $script:VerifyFailed = $true
        Info "$errors issue(s) found"
    }
}

function Doctor {
    Refresh-ProcessPath
    Verify
}

function Assert-WindowsHealthy {
    Doctor
    if ($script:VerifyFailed) { throw "Windows installation verification failed" }
}

function SetupDotfiles {
    Info "Setting up dotfiles..."
    UpdateRepo
    InstallManagedPackages
    SetupSymlinks
    Sync-LazyVim
    if (-not $script:Dry) { Assert-WindowsHealthy }
    Success "Done!"
}

function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update      Update system packages
  packages    Install all managed packages only
  doctor      Detect Windows installation issues
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
        "packages"  { InstallManagedPackages }
        "doctor"    { Doctor; if ($script:VerifyFailed) { exit 1 } }
        "verify"    { Verify; if ($script:VerifyFailed) { exit 1 } }
        default     { Fail "Unknown command: $command"; ShowUsage }
    }
}
