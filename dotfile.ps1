param(
    # When set, skip main dispatch so the script can be
    # dot-sourced by tests to load functions without side effects.
    [switch]$NoMain,
    # Internal recursion guard used only after UpdateRepo starts this script again.
    [switch]$AfterUpdate,
    [Alias('d')][switch]$Dry,
    [Alias('f')][switch]$Force,
    [Alias('q')][switch]$Quiet,
    [Alias('h')][switch]$Help,
    [Parameter(Position = 0)][string]$Command = 'all',
    [Parameter(Position = 1)][string]$UpdateTarget = ''
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
# Don't re-initialise $script:Dry/Quiet/Force here - at a script's top level,
# `$script:X` is the same variable as the param `$X`, so re-assigning would
# clobber values the binder just set from `-d`/`-f`/`-q` flags. Switch params
# already default to $false, which is all the reset was ever providing.
# Resolve symlink so invoking via ~\.local\bin points back to the real repo.
# Allow override via $env:DOTFILES_DIR so the install path is not hardcoded.
$script:DotfilesDir = Resolve-DotfilesDir $env:DOTFILES_DIR $PSCommandPath
$script:FiraCodeNerdFontVersion = '3.5.0'
$script:FiraCodeNerdFontUrl = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.0/FiraCode.zip'
$script:FiraCodeNerdFontSha256 = '8ad2834d8ea1945d8ab042538e608f6370573a29913aa94b5e6bbc92ffacbab5'

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
    $current = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if ($null -eq $current) { return $null }

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

        if ($script:SkipAll) {
            Success "Skipped $source"
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
            $backupPath = "$destination.bak"
            for ($suffix = 1; Get-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue; $suffix++) {
                $backupPath = "$destination.bak.$suffix"
            }
            Rename-Item -LiteralPath $destination -NewName (Split-Path $backupPath -Leaf) -ErrorAction Stop
            Success "Moved $destination to $backupPath"
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
    winget @Arguments --disable-interactivity --accept-package-agreements --accept-source-agreements
    # WinGet reports an already-current package as APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE.
    if ($Arguments[0] -eq 'upgrade' -and $LASTEXITCODE -eq -1978335189) { return }
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function UpdateRepo {
    Info "Updating dotfiles repo..."
    if (-not $script:Dry) {
        git -C $script:DotfilesDir pull --rebase --autostash
        if ($LASTEXITCODE -ne 0) { Fail "Failed to pull dotfiles repo" }
    }
    Success "Finished updating repo"
}

function Get-InstalledWingetPackages {
    $output = Join-Path ([IO.Path]::GetTempPath()) "winget-$([Guid]::NewGuid().ToString('N')).json"
    try {
        winget export --output $output --include-versions --disable-interactivity --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'winget package inventory failed' }
        return @((Get-Content -Raw -LiteralPath $output | ConvertFrom-Json).Sources.Packages.PackageIdentifier)
    } finally {
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
    }
}

function Get-WingetPackages {
    @(
        "Microsoft.PowerShell", "Git.Git", "GnuPG.Gpg4win", "Microsoft.WindowsTerminal",
        "Neovim.Neovim", "Starship.Starship", "JesseDuffield.lazygit",
        "BurntSushi.ripgrep.MSVC", "sharkdp.fd", "junegunn.fzf",
        "tree-sitter.tree-sitter-cli", "LLVM.LLVM",
        "Schniz.fnm", "jj-vcs.jj", "ajeetdsouza.zoxide", "jqlang.jq",
        "Python.Python.3.14", "GitHub.cli", "Notepad++.Notepad++", "koalaman.shellcheck"
    )
}

function Get-RequiredCommands {
    @(
        "git", "gpg", "nvim", "starship", "fzf", "fd", "rg", "lazygit",
        "fnm", "node", "jj", "zoxide", "jq", "codex", "pi",
        "codebase-memory-mcp", "fff-mcp", "fff-mcp-agent", "py", "gh", "vtsls",
        "bash-language-server", "shellcheck", "tree-sitter", "clang"
    )
}

function Invoke-NativeChecked($FailureMessage, [scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}

function Expand-WindowsTarArchive($Archive, $Destination) {
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { throw 'Windows tar command not found' }
    & $tar -xzf $Archive -C $Destination
}

function InstallPackages {
    param([switch]$Update)
    Info "Installing packages..."
    if ($script:Dry) { return }

    $wingetPkgs = @(Get-WingetPackages)
    Info "Checking winget packages ($($wingetPkgs.Count) total)..."
    $installed = @(Get-InstalledWingetPackages)
    $missing = @($wingetPkgs | Where-Object { $_ -notin $installed })
    if ($missing.Count -gt 0) {
        Info "Installing $($missing.Count) missing winget package(s): $($missing -join ', ')"
        foreach ($pkg in $missing) {
            Invoke-Winget "winget install $pkg failed" @('install', '--id', $pkg, '--exact')
        }
    } else {
        Success "All winget packages already installed"
    }

    if ($Update) {
        Info "Upgrading managed winget packages..."
        foreach ($pkg in $wingetPkgs) {
            Invoke-Winget "winget upgrade $pkg failed" @('upgrade', '--id', $pkg, '--exact')
        }
    }

    AddToUserPath (Join-Path $env:ProgramFiles 'LLVM\bin')
    Success "Finished installing packages"
}

function Get-StreamSha256($Stream) {
    return (Get-FileHash -InputStream $Stream -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FileSha256($Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Grant-FontReadAccess($Path) {
    foreach ($sid in 'S-1-15-2-1', 'S-1-15-2-2') {
        icacls $Path /grant "*$sid`:(OI)(CI)(RX)" /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to grant packaged apps font access" }
    }
}

function InstallFiraCodeNerdFont {
    param([switch]$Update)
    Info "Installing FiraCode Nerd Font..."
    if ($script:Dry) { return }

    $fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $styles = @('Bold', 'Light', 'Medium', 'Regular', 'Retina', 'SemiBold')
    $families = @('FiraCodeNerdFont', 'FiraCodeNerdFontMono', 'FiraCodeNerdFontPropo')
    $complete = $true
    foreach ($family in $families) {
        foreach ($style in $styles) {
            if (-not (Test-Path -LiteralPath (Join-Path $fontDir "$family-$style-$script:FiraCodeNerdFontVersion.ttf") -PathType Leaf)) {
                $complete = $false
                break
            }
        }
        if (-not $complete) { break }
    }
    if ($complete -and -not $script:Force) {
        $registry = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        Grant-FontReadAccess $fontDir
        foreach ($family in $families) {
            foreach ($style in $styles) {
                $baseName = "$family-$style"
                $target = Join-Path $fontDir "$baseName-$script:FiraCodeNerdFontVersion.ttf"
                New-ItemProperty -Path $registry -Name "$baseName (TrueType)" -Value $target -Force | Out-Null
            }
        }
        Success "FiraCode Nerd Font $script:FiraCodeNerdFontVersion already installed"
        return
    }

    $archive = Join-Path ([IO.Path]::GetTempPath()) "FiraCode-$([Guid]::NewGuid().ToString('N')).zip"
    $extract = Join-Path ([IO.Path]::GetTempPath()) "FiraCode-$([Guid]::NewGuid().ToString('N'))"
    try {
        Invoke-WebRequest -Uri $script:FiraCodeNerdFontUrl -OutFile $archive -UseBasicParsing
        if ((Get-FileSha256 $archive) -ne $script:FiraCodeNerdFontSha256) {
            throw "FiraCode Nerd Font checksum mismatch"
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $extract
        $registry = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $fonts = @(Get-ChildItem -LiteralPath $extract -File | Where-Object Extension -In '.ttf', '.otf')
        if ($fonts.Count -eq 0) { throw "FiraCode Nerd Font archive contains no fonts" }
        New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
        Grant-FontReadAccess $fontDir
        foreach ($font in $fonts) {
            $targetName = "$($font.BaseName)-$script:FiraCodeNerdFontVersion$($font.Extension)"
            $target = Join-Path $fontDir $targetName
            if (-not (Test-Path -LiteralPath $target) -or (Get-FileSha256 $font.FullName) -ne (Get-FileSha256 $target)) {
                Copy-Item -LiteralPath $font.FullName -Destination $target -Force
            }
            New-ItemProperty -Path $registry -Name "$($font.BaseName) (TrueType)" -Value $target -Force | Out-Null
        }
    } finally {
        Remove-Item -LiteralPath $archive, $extract -Recurse -Force -ErrorAction SilentlyContinue
    }

    Success "Finished installing FiraCode Nerd Font"
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($env:Path, $machinePath, $userPath) -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Get-PiExtensionsPins {
    $path = Join-Path $script:DotfilesDir "packages\pi-extensions-release.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Pi extension release pins not found: $path" }
    $pins = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ([string]$pins.releaseId -notmatch '^[0-9a-f]{64}$') { throw "Invalid Pi extension release ID" }
    if ([string]$pins.node.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Pi extension Node version" }
    if ([string]$pins.node.abi -notmatch '^\d+$') { throw "Invalid Pi extension Node ABI" }
    if ([string]$pins.betterSqlite3.version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid better-sqlite3 version" }
    foreach ($key in 'windows-x64', 'windows-arm64') {
        $asset = $pins.betterSqlite3.assets.$key
        if (-not $asset -or [string]$asset.file -notmatch '^better-sqlite3-[0-9A-Za-z.-]+\.tar\.gz$' -or [string]$asset.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Invalid better-sqlite3 asset pins for $key"
        }
    }
    return $pins
}

function InstallFnm {
    Info "Installing Node.js LTS via fnm..."
    if ($script:Dry) { return }

    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        Refresh-ProcessPath
    }
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
        FailSoft "fnm not found on PATH. Skipping Node.js LTS install - open a new shell and re-run 'dotfile.ps1'."
        return
    }

    $nodeVersion = [string](Get-PiExtensionsPins).node.version
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    Invoke-NativeChecked "fnm install $nodeVersion failed" { fnm install $nodeVersion }
    Invoke-NativeChecked "fnm use $nodeVersion failed" { fnm use $nodeVersion }
    Invoke-NativeChecked "fnm default $nodeVersion failed" { fnm default $nodeVersion }

    Success "Finished installing pinned Node.js"
}

function InstallExtras {
    param([switch]$Update)
    InstallFiraCodeNerdFont -Update:$Update
}

function InstallManagedPackages {
    InstallPackages
    InstallExtras
    InstallAi
}

function Get-CodexWindowsTarget($Architecture) {
    switch ([string]$Architecture) {
        "X64" { return "x86_64-pc-windows-msvc" }
        "Arm64" { return "aarch64-pc-windows-msvc" }
        default { throw "Unsupported Codex Windows architecture: $Architecture" }
    }
}

function Get-CodexPathValue($PathValue, $BinDir, $ManagedRoot) {
    $managedRootNormalized = $ManagedRoot.TrimEnd([char[]](92, 47))
    $legacyBin = Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin"
    $entries = @($PathValue -split ";" | Where-Object {
        if (-not $_) { return $false }
        $entry = $_.TrimEnd([char[]](92, 47))
        return $entry -ine $BinDir.TrimEnd([char[]](92, 47)) -and
            $entry -ine $legacyBin.TrimEnd([char[]](92, 47)) -and
            -not $entry.StartsWith($managedRootNormalized + [char]92, [StringComparison]::OrdinalIgnoreCase) -and
            -not $entry.StartsWith($managedRootNormalized + [char]47, [StringComparison]::OrdinalIgnoreCase)
    })
    return (@($BinDir) + $entries) -join ";"
}

function Test-CodexRelease($ReleaseDir, $ExpectedVersion) {
    foreach ($relativePath in @(
        "codex-package.json",
        "bin\codex.exe",
        "bin\codex-code-mode-host.exe",
        "codex-path\rg.exe",
        "codex-resources\codex-command-runner.exe",
        "codex-resources\codex-windows-sandbox-setup.exe"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $relativePath) -PathType Leaf)) { return $false }
    }

    try {
        $versionOutput = & (Join-Path $ReleaseDir "bin\codex.exe") --version 2>$null
    } catch {
        return $false
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    $match = [regex]::Match(($versionOutput -join " "), "([0-9][0-9A-Za-z.+-]*)$")
    return $match.Success -and $match.Groups[1].Value -ceq $ExpectedVersion
}

function Set-CodexActivePath($BinDir, $ManagedRoot) {
    $oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    try {
        [Environment]::SetEnvironmentVariable("Path", (Get-CodexPathValue $oldUserPath $BinDir $ManagedRoot), "User")
    } catch {
        [Environment]::SetEnvironmentVariable("Path", $oldUserPath, "User")
        throw
    }
}

function InstallCodex {
    param([switch]$Update)
    Info "Installing Codex CLI..."
    if ($script:Dry) { return }
    if (-not [Environment]::Is64BitOperatingSystem) { throw "Codex requires 64-bit Windows" }

    $pinsPath = Join-Path $script:DotfilesDir "packages\codex-release.json"
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing Codex pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid pinned Codex version: $version" }

    $target = Get-CodexWindowsTarget ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
    $architecture = if ($target.StartsWith("x86_64")) { "x86_64" } else { "aarch64" }
    $expectedHash = [string]$pins.windows.$architecture
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') { throw "Invalid pinned Codex checksum for $architecture" }

    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE ".codex" } else { $env:CODEX_HOME }
    $standaloneRoot = Join-Path $codexHome "packages\standalone"
    $releasesDir = Join-Path $standaloneRoot "releases"
    $releaseDir = Join-Path $releasesDir "$version-$target-$($expectedHash.Substring(0, 12))"
    $binDir = Join-Path $releaseDir "bin"
    New-Item -ItemType Directory -Force -Path $standaloneRoot | Out-Null
    $installLock = [IO.File]::Open((Join-Path $standaloneRoot "install.lock"), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    try {
        if ((Test-Path -LiteralPath $releaseDir) -and -not (Test-CodexRelease $releaseDir $version)) {
            throw "Pinned Codex release is incomplete: $releaseDir"
        }
        if (-not (Test-Path -LiteralPath $releaseDir)) {
            New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) "codex-install-$([Guid]::NewGuid().ToString('N'))"
            $stagingDir = Join-Path $releasesDir ".staging.$([Guid]::NewGuid().ToString('N'))"
            $archive = Join-Path $tempDir "codex-package-$target.tar.gz"
            $archiveLock = $null
            try {
                New-Item -ItemType Directory -Force -Path $tempDir, $stagingDir | Out-Null
                $uri = "https://github.com/openai/codex/releases/download/rust-v$version/codex-package-$target.tar.gz"
                Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
                $archiveLock = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if ((Get-StreamSha256 $archiveLock) -ne $expectedHash) { throw "Codex package checksum mismatch" }
                Invoke-NativeChecked "Codex package extraction failed" { Expand-WindowsTarArchive $archive $stagingDir }
                if (-not (Test-CodexRelease $stagingDir $version)) { throw "Codex package is incomplete or has wrong version" }
                $archiveLock.Dispose()
                $archiveLock = $null
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction Stop
                Move-Item -LiteralPath $stagingDir -Destination $releaseDir
            } catch {
                $operationError = $_
                if ($archiveLock) { $archiveLock.Dispose(); $archiveLock = $null }
                $cleanupError = $null
                foreach ($path in $tempDir, $stagingDir) {
                    try {
                        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
                    } catch {
                        if (-not $cleanupError) { $cleanupError = $_.Exception }
                    }
                }
                if ($cleanupError) { throw "Codex cleanup failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
                throw $operationError
            } finally {
                if ($archiveLock) { $archiveLock.Dispose() }
            }
        }

        if (-not (Test-CodexRelease $releaseDir $version)) { throw "Installed Codex release verification failed" }
        Set-CodexActivePath $binDir $releasesDir
    } finally {
        $installLock.Dispose()
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
        $applySeed = ''
        Invoke-NativeChecked 'Codex config seed comparison failed' {
            py -3.14 (Join-Path $script:DotfilesDir 'scripts\seed_merge\codex.py') $target $source $applySeed
        }
    }
    (Get-Item -LiteralPath $target).IsReadOnly = $false
}

function Get-PinnedPiVersion {
    $lockPath = Join-Path $script:DotfilesDir 'packages\pi-agent-npm-shrinkwrap.json'
    if (-not (Test-Path -LiteralPath $lockPath)) { throw "Missing Pi package lock: $lockPath" }
    $content = Get-Content -Raw -LiteralPath $lockPath
    $packagesIndex = $content.IndexOf('"packages"', [StringComparison]::Ordinal)
    if ($packagesIndex -lt 0) { throw "Failed to parse pinned Pi package lock: $lockPath" }
    try { $root = ($content.Substring(0, $packagesIndex) + '"packages": {}}') | ConvertFrom-Json } catch { throw "Failed to parse pinned Pi package lock: $lockPath" }
    $version = [string]$root.version
    if ([string]$root.name -ne '@earendil-works/pi-coding-agent' -or $version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        throw "Invalid pinned Pi package lock: $lockPath"
    }
    return $version
}

function Get-PinnedPiSourceHash {
    $packagePath = Join-Path $script:DotfilesDir 'packages\pi-agent.nix'
    $content = Get-Content -Raw -LiteralPath $packagePath
    $match = [regex]::Match($content, '(?m)^\s*hash\s*=\s*"(sha256-[A-Za-z0-9+/=]+)";')
    if (-not $match.Success) { throw "Pi package source hash missing: $packagePath" }
    return $match.Groups[1].Value
}

function Get-PiSourceDigest($Expected) {
    $match = [regex]::Match($Expected, '^sha256-([A-Za-z0-9+/=]+)$')
    if (-not $match.Success) { throw 'Invalid Pi source hash' }
    try { return [Convert]::FromBase64String($match.Groups[1].Value) } catch { throw 'Invalid Pi source hash' }
}

function Test-PiSourceHash($Stream, $Expected) {
    $Stream.Position = 0
    $actual = [Security.Cryptography.SHA256]::Create().ComputeHash($Stream)
    $Stream.Position = 0
    return [Convert]::ToBase64String($actual) -ceq [Convert]::ToBase64String((Get-PiSourceDigest $Expected))
}

function Get-PiExtensionsWindowsArch($Architecture = $env:PROCESSOR_ARCHITECTURE) {
    switch ([string]$Architecture) {
        'AMD64' { return 'windows-x64' }
        'X64' { return 'windows-x64' }
        'ARM64' { return 'windows-arm64' }
        'Arm64' { return 'windows-arm64' }
        default { throw "Unsupported Pi extension Windows architecture: $Architecture" }
    }
}

function Test-PiExtensionsRelease($ReleaseDir, $Pins) {
    if (-not (Test-Path -LiteralPath $ReleaseDir -PathType Container)) { return $false }
    $releaseItem = Get-Item -LiteralPath $ReleaseDir -Force
    if (($releaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    $lockPath = Join-Path $ReleaseDir 'package-lock.json'
    $packagePath = Join-Path $ReleaseDir 'package.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf) -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return $false }
    if ((Get-FileSha256 $lockPath) -ne [string]$Pins.releaseId) { return $false }
    try { $manifest = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json } catch { return $false }
    $nodeModules = Join-Path $ReleaseDir 'node_modules'
    foreach ($dependency in $manifest.dependencies.PSObject.Properties) {
        $installedManifest = Join-Path (Join-Path $nodeModules $dependency.Name) 'package.json'
        if (-not (Test-Path -LiteralPath $installedManifest -PathType Leaf)) { return $false }
        try { $installed = Get-Content -Raw -LiteralPath $installedManifest | ConvertFrom-Json } catch { return $false }
        if ([string]$installed.version -ne [string]$dependency.Value) { return $false }
    }
    $mcpIndex = Join-Path $nodeModules 'pi-mcp-extension\src\index.ts'
    if (-not (Test-Path -LiteralPath $mcpIndex -PathType Leaf)) { return $false }
    try {
        if ((Get-Content -Raw -LiteralPath $mcpIndex) -notlike '*if (process.env.PI_SUBAGENT_DEPTH) await eagerStartup;*') { return $false }
    } catch { return $false }
    $hermesHandlers = Join-Path $nodeModules 'pi-hermes-memory\src\handlers'
    $hermesSessionFlush = Join-Path $hermesHandlers 'session-flush.ts'
    $hermesChildProcess = Join-Path $hermesHandlers 'pi-child-process.ts'
    $hermesWatchdog = Join-Path $hermesHandlers 'child-process-watchdog.mjs'
    if (-not (Test-Path -LiteralPath $hermesSessionFlush -PathType Leaf) -or
        -not (Test-Path -LiteralPath $hermesChildProcess -PathType Leaf) -or
        -not (Test-Path -LiteralPath $hermesWatchdog -PathType Leaf)) { return $false }
    try {
        if ((Get-Content -Raw -LiteralPath $hermesSessionFlush) -notlike '*execDetachedChildPrompt*') { return $false }
        if ((Get-Content -Raw -LiteralPath $hermesChildProcess) -notlike '*"--cleanup-dir"*') { return $false }
        if ((Get-Content -Raw -LiteralPath $hermesWatchdog) -notlike '*cleanupPromptDirectory*') { return $false }
    } catch { return $false }
    $betterManifest = Join-Path $nodeModules 'better-sqlite3\package.json'
    $betterBinary = Join-Path $nodeModules 'better-sqlite3\build\Release\better_sqlite3.node'
    if (-not (Test-Path -LiteralPath $betterManifest -PathType Leaf) -or -not (Test-Path -LiteralPath $betterBinary -PathType Leaf)) { return $false }
    try { $better = Get-Content -Raw -LiteralPath $betterManifest | ConvertFrom-Json } catch { return $false }
    return [string]$better.version -eq [string]$Pins.betterSqlite3.version
}

function InstallPiExtensions {
    Info "Installing integrity-locked Pi extensions..."
    if ($script:Dry) { return }

    $pins = Get-PiExtensionsPins
    $source = Join-Path $script:DotfilesDir 'config\shared\ai\pi\extensions'
    $sourceLock = Join-Path $source 'package-lock.json'
    if (-not (Test-Path -LiteralPath $sourceLock -PathType Leaf) -or (Get-FileSha256 $sourceLock) -ne [string]$pins.releaseId) {
        throw "Pi extension package lock does not match release pins"
    }
    foreach ($command in 'node', 'npm', 'py', 'tar') {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command command not found for Pi extensions" }
    }
    $nodeVersion = (& node --version 2>$null | Select-Object -Last 1).TrimStart('v')
    if ($LASTEXITCODE -ne 0 -or $nodeVersion -ne [string]$pins.node.version) { throw "Pi extensions require Node $($pins.node.version)" }
    $nodeAbi = (& node -p 'process.versions.modules' 2>$null | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or $nodeAbi -ne [string]$pins.node.abi) { throw "Pi extensions require Node ABI $($pins.node.abi)" }

    $asset = $pins.betterSqlite3.assets.(Get-PiExtensionsWindowsArch)
    $root = Join-Path $env:USERPROFILE '.pi\agent\locked-extensions'
    $releases = Join-Path $root 'releases'
    $release = Join-Path $releases ([string]$pins.releaseId)
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $installLock = [IO.File]::Open((Join-Path $root 'install.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if (Test-Path -LiteralPath $release) {
            if (-not (Test-PiExtensionsRelease $release $pins)) { throw "Pinned Pi extension release is incomplete: $release" }
            return
        }

        New-Item -ItemType Directory -Force -Path $releases | Out-Null
        $staging = Join-Path $releases ".staging.$([Guid]::NewGuid().ToString('N'))"
        $archive = Join-Path $staging ([string]$asset.file)
        try {
            New-Item -ItemType Directory -Force -Path $staging | Out-Null
            Copy-Item -LiteralPath (Join-Path $source 'package.json'), $sourceLock -Destination $staging
            $stagedLock = Join-Path $staging 'package-lock.json'
            $lockStream = [IO.File]::Open($stagedLock, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ((Get-StreamSha256 $lockStream) -ne [string]$pins.releaseId) { throw "Staged Pi extension package lock mismatch" }
                Invoke-NativeChecked "Pi extension npm ci failed" { npm ci --prefix $staging --omit=dev --ignore-scripts --legacy-peer-deps }
                $patch = Join-Path $script:DotfilesDir 'scripts\patch_pi_mcp_background.py'
                $mcpIndex = Join-Path $staging 'node_modules\pi-mcp-extension\src\index.ts'
                Invoke-NativeChecked "Pi MCP background startup repair failed" { py -3.14 $patch $mcpIndex }
                $hermesPatch = Join-Path $script:DotfilesDir 'scripts\patch_pi_hermes_background_flush.py'
                $hermesRoot = Join-Path $staging 'node_modules\pi-hermes-memory'
                Invoke-NativeChecked "Pi Hermes background shutdown flush repair failed" { py -3.14 $hermesPatch $hermesRoot }
            } finally { $lockStream.Dispose() }

            $uri = "https://github.com/WiseLibs/better-sqlite3/releases/download/v$($pins.betterSqlite3.version)/$($asset.file)"
            Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
            $archiveStream = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                if ((Get-StreamSha256 $archiveStream) -ne [string]$asset.sha256) { throw "better-sqlite3 package checksum mismatch" }
                $betterDir = Join-Path $staging 'node_modules\better-sqlite3'
                Invoke-NativeChecked "better-sqlite3 package extraction failed" { Expand-WindowsTarArchive $archive $betterDir }
            } finally { $archiveStream.Dispose() }
            Remove-Item -LiteralPath $archive -Force -ErrorAction Stop
            if (-not (Test-PiExtensionsRelease $staging $pins)) { throw "Installed Pi extension release verification failed" }
            Move-Item -LiteralPath $staging -Destination $release
        } finally {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
        }
    } finally { $installLock.Dispose() }

    Success "Finished installing integrity-locked Pi extensions"
}

function RepairPiCompactionSteering {
    param([string]$AgentSessionPath)

    if (-not $AgentSessionPath) {
        $piCommand = Get-Command pi -ErrorAction SilentlyContinue
        if (-not $piCommand) { throw "pi command not found for compaction repair" }
        $AgentSessionPath = Join-Path (Split-Path -Parent $piCommand.Source) 'node_modules\@earendil-works\pi-coding-agent\dist\core\agent-session.js'
    }
    if (-not (Test-Path -LiteralPath $AgentSessionPath -PathType Leaf)) {
        throw "Pi agent session runtime not found: $AgentSessionPath"
    }
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        throw "py is required to repair Pi compaction steering"
    }

    $patch = Join-Path $script:DotfilesDir 'scripts\patch_pi_compaction.py'
    Invoke-NativeChecked "Pi compaction steering repair failed" {
        py -3.14 $patch $AgentSessionPath
    }
}

function Get-PiReleaseDigest($ReleaseDir) {
    $root = [IO.Path]::GetFullPath($ReleaseDir).TrimEnd([char[]](92, 47))
    $rows = foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
        if ($file.Name -eq '.release.sha256') { continue }
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        "$relative`n$((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha256.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() } finally { $sha256.Dispose() }
}

function Test-PiRelease($ReleaseDir, $Version, $Shrinkwrap) {
    $manifest = Join-Path $ReleaseDir 'package.json'
    $lock = Join-Path $ReleaseDir 'npm-shrinkwrap.json'
    $entry = Join-Path $ReleaseDir 'dist\cli.js'
    $session = Join-Path $ReleaseDir 'dist\core\agent-session.js'
    $digest = Join-Path $ReleaseDir '.release.sha256'
    foreach ($path in $manifest, $lock, $entry, $session, $digest) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    }
    if ((Get-Content -Raw -LiteralPath $lock) -cne $Shrinkwrap) { return $false }
    if ((Get-Content -Raw -LiteralPath $digest).Trim() -cne (Get-PiReleaseDigest $ReleaseDir)) { return $false }
    $sessionContent = Get-Content -Raw -LiteralPath $session
    if (-not $sessionContent.Contains('this._autoCompactionAbortController = undefined;') -or -not $sessionContent.Contains('await this.waitForIdle();')) { return $false }
    try { $json = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json } catch { return $false }
    foreach ($dependency in $json.dependencies.PSObject.Properties.Name) {
        if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir "node_modules\$dependency\package.json") -PathType Leaf)) { return $false }
    }
    return [string]$json.version -ceq $Version
}

function InstallPi {
    param([switch]$Update)
    Info "Installing Pi coding agent..."
    if ($script:Dry) { return }
    $version = Get-PinnedPiVersion
    $lockPath = Join-Path $script:DotfilesDir 'packages\pi-agent-npm-shrinkwrap.json'
    $shrinkwrap = Get-Content -Raw -LiteralPath $lockPath
    $sourceHash = Get-PinnedPiSourceHash
    $releaseId = -join ((Get-PiSourceDigest $sourceHash) | ForEach-Object { $_.ToString('x2') })
    $root = Join-Path $env:LOCALAPPDATA 'dotfiles\pi'
    $releases = Join-Path $root 'releases'
    $release = Join-Path $releases "$version-$($releaseId.Substring(0,12))"
    $bin = Join-Path $root 'bin'
    New-Item -ItemType Directory -Force -Path $releases, $bin | Out-Null
    $guard = [IO.File]::Open((Join-Path $root 'install.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        if (-not (Test-PiRelease $release $version $shrinkwrap)) {
            if (Test-Path -LiteralPath $release) { throw "Pinned Pi release is incomplete: $release" }
            $stage = Join-Path $releases ".staging.$([Guid]::NewGuid().ToString('N'))"
            $archive = Join-Path ([IO.Path]::GetTempPath()) "pi-$([Guid]::NewGuid().ToString('N')).tgz"
            $stream = $null
            try {
                New-Item -ItemType Directory -Force -Path $stage | Out-Null
                Invoke-WebRequest -Uri "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-$version.tgz" -OutFile $archive -UseBasicParsing
                $stream = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if (-not (Test-PiSourceHash $stream $sourceHash)) { throw 'Pi package checksum mismatch' }
                Invoke-NativeChecked 'Pi package extraction failed' { Expand-WindowsTarArchive $archive $stage }
                $package = Join-Path $stage 'package'
                if (-not (Test-Path -LiteralPath $package)) { throw 'Pi package archive missing package directory' }
                $embeddedLock = Join-Path $package 'npm-shrinkwrap.json'
                if (-not (Test-Path -LiteralPath $embeddedLock)) { throw 'Pi package archive missing npm shrinkwrap' }
                Invoke-NativeChecked 'Pi embedded npm shrinkwrap mismatch' {
                    node -e 'const fs=require("fs");const clean=v=>Array.isArray(v)?v.map(clean):v&&typeof v==="object"?Object.fromEntries(Object.keys(v).filter(k=>k!=="integrity").sort().map(k=>[k,clean(v[k])])):v;const a=clean(JSON.parse(fs.readFileSync(process.argv[1],"utf8")));const b=clean(JSON.parse(fs.readFileSync(process.argv[2],"utf8")));process.exit(JSON.stringify(a)===JSON.stringify(b)?0:1)' $embeddedLock $lockPath
                }
                Copy-Item -LiteralPath $lockPath -Destination $embeddedLock -Force
                $manifestPath = Join-Path $package 'package.json'
                $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
                $manifest.PSObject.Properties.Remove('devDependencies')
                [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
                Invoke-NativeChecked 'Pi npm ci failed' { npm ci --prefix $package --omit=dev --ignore-scripts }
                if ((Get-Content -Raw -LiteralPath $embeddedLock) -cne $shrinkwrap) { throw 'Pi npm install changed the reviewed shrinkwrap' }
                RepairPiCompactionSteering (Join-Path $package 'dist\core\agent-session.js')
                [IO.File]::WriteAllText((Join-Path $package '.release.sha256'), (Get-PiReleaseDigest $package), [Text.Encoding]::ASCII)
                if (-not (Test-PiRelease $package $version $shrinkwrap)) { throw 'Installed Pi package is incomplete or has wrong version' }
                Move-Item -LiteralPath $package -Destination $release
            } finally {
                if ($stream) { $stream.Dispose() }
                Remove-Item -LiteralPath $archive, $stage -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not (Test-PiRelease $release $version $shrinkwrap)) { throw 'Installed Pi release verification failed' }
        $launcher = Join-Path $bin 'pi.cmd'
        $launcherTemporary = "$launcher.tmp.$([Guid]::NewGuid().ToString('N'))"
        try {
            "@echo off`r`nnode `"$release\dist\cli.js`" %*" | Set-Content -LiteralPath $launcherTemporary -Encoding ascii
            Move-Item -LiteralPath $launcherTemporary -Destination $launcher -Force
        } finally { Remove-Item -LiteralPath $launcherTemporary -Force -ErrorAction SilentlyContinue }
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $entries = @($userPath -split ';' | Where-Object { $_ -and $_ -ine $bin })
        [Environment]::SetEnvironmentVariable('Path', (@($bin) + $entries) -join ';', 'User')
        $processEntries = @($env:Path -split ';' | Where-Object { $_ -and $_ -ine $bin })
        $env:Path = (@($bin) + $processEntries) -join ';'
    } finally { $guard.Dispose() }
    Success "Finished installing Pi coding agent"
}

function InstallPiLanguageServers {
    param([switch]$Update)
    Info "Installing Pi language servers..."
    if ($script:Dry) { return }

    $servers = [ordered]@{
        'vtsls' = '0.3.0'
        'bash-language-server' = '5.6.0'
    }
    $needsInstall = $false
    foreach ($name in $servers.Keys) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            $needsInstall = $true
            continue
        }
        $version = & $name --version 2>$null | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0 -or -not $version -or $version.Trim() -ne $servers[$name]) {
            $needsInstall = $true
        }
    }

    if ($needsInstall) {
        Invoke-NativeChecked "Pi language-server install failed" {
            npm install --global @vtsls/language-server@0.3.0 bash-language-server@5.6.0
        }
    }
    if (-not (Get-Command shellcheck -ErrorAction SilentlyContinue)) {
        Invoke-Winget "ShellCheck install failed" @('install', '--id', 'koalaman.shellcheck', '--exact')
    }
    Refresh-ProcessPath

    foreach ($name in $servers.Keys) {
        $version = & $name --version 2>$null | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0 -or -not $version -or $version.Trim() -ne $servers[$name]) {
            throw "$name $($servers[$name]) not found after installation"
        }
    }
    if (-not (Get-Command shellcheck -ErrorAction SilentlyContinue)) {
        throw "shellcheck not found after installation"
    }
    Success "Finished installing Pi language servers"
}

function SyncPiConfigs {
    Info "Syncing Pi configuration..."
    if ($script:Dry) { return }

    $seedDir = Join-Path $script:DotfilesDir "config\shared\ai\pi"
    $targetDir = Join-Path $env:USERPROFILE ".pi\agent"
    $baseDir = Join-Path $env:LOCALAPPDATA "dotfiles\pi"
    New-Item -ItemType Directory -Force -Path $targetDir, $baseDir | Out-Null

    foreach ($name in @("settings.json", "keybindings.json", "web-search.json", "mcp.json", "subagent-config.json")) {
        $source = if ($name -eq "mcp.json") {
            Join-Path $script:DotfilesDir "config\windows\ai\pi\mcp.json"
        } else {
            Join-Path $seedDir $name
        }
        $relative = if ($name -eq "subagent-config.json") {
            "extensions\subagent\config.json"
        } elseif ($name -eq "web-search.json") {
            "..\web-search.json"
        } else {
            $name
        }
        $target = Join-Path $targetDir $relative
        $base = Join-Path $baseDir $name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        if ($name -eq "subagent-config.json") {
            foreach ($destination in $target, $base) {
                $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                if ($destinationItem -and -not $destinationItem.PSIsContainer -and
                    -not ($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                    (Get-FileSha256 $source) -eq (Get-FileSha256 $destination)) {
                    continue
                }
                $temp = "$destination.tmp.$([Guid]::NewGuid().ToString('N'))"
                Copy-Item -LiteralPath $source -Destination $temp
                Move-Item -LiteralPath $temp -Destination $destination -Force
            }
            continue
        }
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $source -Destination $target
            Copy-Item -LiteralPath $source -Destination $base
            continue
        }

        if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
            throw "py is required to sync Pi configuration"
        }

        $mergeScript = Join-Path $script:DotfilesDir "scripts\seed_merge\pi.py"
        $applySeed = if ((Get-Item -LiteralPath $source).IsReadOnly) { "" } else { $source }
        Invoke-NativeChecked "Pi $name seed comparison failed" {
            py -3.14 $mergeScript $target $source $applySeed $base
        }
    }

    $extensionDir = Join-Path $targetDir "extensions"
    New-Item -ItemType Directory -Force -Path $extensionDir | Out-Null
    $directCopies = @(
        @{
            Source = Join-Path $script:DotfilesDir 'config\windows\ai\pi\pi-lsp.json'
            Destination = Join-Path $targetDir 'pi-lsp.json'
        }
    )
    foreach ($name in @("caveman-default.js", "ponytail-default.js", "codex-status.js", "windows-exit.js")) {
        $directCopies += @{
            Source = Join-Path $seedDir $name
            Destination = Join-Path $extensionDir $name
        }
    }
    foreach ($copy in $directCopies) {
        $destinationItem = Get-Item -LiteralPath $copy.Destination -Force -ErrorAction SilentlyContinue
        if ($destinationItem -and -not $destinationItem.PSIsContainer -and
            -not ($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Get-FileSha256 $copy.Source) -eq (Get-FileSha256 $copy.Destination)) {
            continue
        }
        if ($destinationItem -and ($destinationItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $copy.Destination -Force
        }
        Copy-Item -LiteralPath $copy.Source -Destination $copy.Destination -Force
    }
    Success "Finished syncing Pi configuration"
}

function InstallFffMcp {
    param([switch]$Update)
    Info "Installing FFF MCP server..."
    if ($script:Dry) { return }

    $pinsPath = Join-Path $script:DotfilesDir 'packages\fff-release.json'
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing FFF pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    $asset = $pins.mcp.'windows-x64'
    $assetFile = [string]$asset.file
    $expectedHash = [string]$asset.sha256
    if ($version -notmatch '^\d+\.\d+\.\d+$' -or $assetFile -ne 'fff-mcp-x86_64-pc-windows-msvc.exe' -or $expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw 'Invalid pinned FFF MCP release'
    }

    $binDir = Join-Path $env:USERPROFILE '.local\bin'
    $destination = Join-Path $binDir 'fff-mcp.exe'
    $current = Test-Path -LiteralPath $destination -PathType Leaf
    if ($current) {
        $current = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedHash
    }
    if (-not $current) {
        $url = "https://github.com/dmtrKovalenko/fff/releases/download/v$version/$assetFile"
        $download = "$destination.download"
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        try {
            Invoke-WebRequest -Uri $url -OutFile $download
            if ((Get-FileHash -Algorithm SHA256 $download).Hash -ne $expectedHash) {
                throw 'FFF MCP download hash mismatch'
            }
            if (Test-Path -LiteralPath $destination) {
                $processes = @(Get-Process -Name 'fff-mcp' -ErrorAction SilentlyContinue)
                $processes | Stop-Process -Force -ErrorAction Stop
                $processes | Wait-Process -Timeout 5 -ErrorAction Stop
                Remove-Item -LiteralPath $destination -Force
            }
            Move-Item -LiteralPath $download -Destination $destination
        } finally {
            Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
        }
    } else {
        Info "Already installed FFF MCP server"
    }
    $launcher = Join-Path $binDir 'fff-mcp-agent.cmd'
    @'
@echo off
"%~dp0fff-mcp.exe" --frecency-db "%LOCALAPPDATA%\fff\frecency" %*
'@ | Set-Content -LiteralPath $launcher -Encoding ascii
    AddToUserPath $binDir

    Success "Finished installing FFF MCP server"
}

function Get-CodebaseMemoryWindowsArch($Architecture) {
    switch ([string]$Architecture) {
        "X64" { return "amd64" }
        "Arm64" { return "arm64" }
        default { throw "Unsupported codebase-memory Windows architecture: $Architecture" }
    }
}

function Get-CodebaseMemoryPathValue($PathValue, $ReleaseDir, $ReleasesRoot, $LegacyRoot) {
    $releasesNormalized = $ReleasesRoot.TrimEnd([char[]](92, 47))
    $releaseNormalized = $ReleaseDir.TrimEnd([char[]](92, 47))
    $legacyNormalized = $LegacyRoot.TrimEnd([char[]](92, 47))
    $entries = @($PathValue -split ";" | Where-Object {
        if (-not $_) { return $false }
        $entry = $_.TrimEnd([char[]](92, 47))
        return $entry -ine $releaseNormalized -and
            $entry -ine $legacyNormalized -and
            -not $entry.StartsWith($releasesNormalized + [char]92, [StringComparison]::OrdinalIgnoreCase) -and
            -not $entry.StartsWith($releasesNormalized + [char]47, [StringComparison]::OrdinalIgnoreCase)
    })
    return (@($ReleaseDir) + $entries) -join ";"
}

function Test-CodebaseMemoryActivePath($ReleaseDir, $ReleasesRoot, $LegacyRoot) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    return (Get-CodebaseMemoryPathValue $userPath $ReleaseDir $ReleasesRoot $LegacyRoot) -ceq $userPath
}

function Set-CodebaseMemoryActivePath($ReleaseDir, $ReleasesRoot, $LegacyRoot) {
    $oldUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    try {
        $newUserPath = Get-CodebaseMemoryPathValue $oldUserPath $ReleaseDir $ReleasesRoot $LegacyRoot
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    } catch {
        [Environment]::SetEnvironmentVariable("Path", $oldUserPath, "User")
        throw
    }
}

function Test-CodebaseMemoryArchive($Archive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $expected = @("codebase-memory-mcp.exe", "LICENSE", "install.ps1", "THIRD_PARTY_NOTICES.md")
        if ($names.Count -ne $expected.Count) { return $false }
        foreach ($name in $expected) {
            if ($names -cnotcontains $name) { return $false }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Get-CodebaseMemoryVersionFromOutput($Output) {
    $match = [regex]::Match(($Output -join " "), "(?:^|\s)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$")
    if ($match.Success) { return $match.Groups[1].Value }
    return ""
}

function Test-CodebaseMemoryRelease($ReleaseDir, $ExpectedVersion) {
    $executable = Join-Path $ReleaseDir "codebase-memory-mcp.exe"
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $executable -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    try {
        $versionOutput = & $executable --version 2>$null
    } catch {
        return $false
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    return (Get-CodebaseMemoryVersionFromOutput $versionOutput) -ceq $ExpectedVersion
}

function Invoke-CodebaseMemoryCommand($Executable, $FailureMessage, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw $FailureMessage }
}



function Remove-CodebaseMemoryPiAdapter($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $Path
    if ($content.Contains('// Generated by codebase-memory-mcp for pi.') -and
        $content.Contains('// codebase-memory-mcp:start') -and
        $content.Contains('// codebase-memory-mcp:end')) {
        Remove-Item -LiteralPath $Path -Force
    }
}


function Remove-CodebaseMemoryPiSkill($Path) {
    $skill = Join-Path $Path 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skill -PathType Leaf)) { return }
    $content = Get-Content -Raw -LiteralPath $skill
    if ($content.Contains('name: codebase-memory') -and
        $content.Contains(('# Codebase Memory {0} Knowledge Graph Tools' -f [char]0x2014)) -and
        $content.Contains('## 15 MCP Tools')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Invoke-CodebaseMemoryTomlTool($Operation, $Path, [string]$Argument = '') {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $tool = Join-Path $script:DotfilesDir 'scripts\seed_merge\toml_tools.py'
    $arguments = @($tool, $Operation, $Path)
    if ($Argument) { $arguments += $Argument }
    $output = if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3.14 @arguments
    } else {
        python3 @arguments
    }
    if ($LASTEXITCODE -ne 0) { throw "Codex TOML repair failed: $Operation" }
    return ($output -join "`n").Trim()
}

function Repair-CodebaseMemoryCodexMcp($Path) { Invoke-CodebaseMemoryTomlTool 'mcp' $Path | Out-Null }
function Suspend-CodebaseMemoryCodexToolApprovals($Path) { Invoke-CodebaseMemoryTomlTool 'suspend' $Path }
function Restore-CodebaseMemoryCodexToolApprovals($Path, $Approvals) { if ($Approvals) { Invoke-CodebaseMemoryTomlTool 'restore' $Path $Approvals | Out-Null } }
function Repair-CodebaseMemoryCodexHooks($Path) { Invoke-CodebaseMemoryTomlTool 'hooks' $Path | Out-Null }

function Stop-CodebaseMemoryProcesses {
    $processes = @(Get-Process -Name 'codebase-memory-mcp' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return }
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    $processes | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
}

function Test-CodebaseMemoryConfigDatabaseAccess($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        return $true
    } catch {
        $exception = $_.Exception
        while ($exception) {
            if ($exception -is [UnauthorizedAccessException]) { return $false }
            $exception = $exception.InnerException
        }
        throw
    } finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Test-CodebaseMemoryManagedState($StatePath, $Version, $ReleaseDir, $Executable, $ConfigDatabase, $ReleasesRoot, $LegacyRoot) {
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $StatePath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    try {
        $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
        if ([string]$state.version -cne $Version -or [string]$state.releaseDir -ine $ReleaseDir) { return $false }

        $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE '.codex' } else { $env:CODEX_HOME }
        $codexConfig = Join-Path $codexHome 'config.toml'
        if (-not (Test-Path -LiteralPath $codexConfig -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $codexConfig -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        if ((Get-FileHash -LiteralPath $codexConfig -Algorithm SHA256).Hash -ine [string]$state.codexConfigSha256) { return $false }

        $piAdapter = Join-Path $env:USERPROFILE '.pi\agent\extensions\cbmem.ts'
        if (Test-Path -LiteralPath $piAdapter -PathType Leaf) {
            $adapterContent = Get-Content -Raw -LiteralPath $piAdapter
            if ($adapterContent.Contains('// Generated by codebase-memory-mcp for pi.') -and
                $adapterContent.Contains('// codebase-memory-mcp:start') -and
                $adapterContent.Contains('// codebase-memory-mcp:end')) { return $false }
        }
        $piSkill = Join-Path $env:USERPROFILE '.pi\agent\skills\codebase-memory\SKILL.md'
        if (Test-Path -LiteralPath $piSkill -PathType Leaf) {
            $skillContent = Get-Content -Raw -LiteralPath $piSkill
            if ($skillContent.Contains('name: codebase-memory') -and
                $skillContent.Contains(('# Codebase Memory {0} Knowledge Graph Tools' -f [char]0x2014)) -and
                $skillContent.Contains('## 15 MCP Tools')) { return $false }
        }
        if (-not (Test-CodebaseMemoryConfigDatabaseAccess $ConfigDatabase)) { return $false }
        foreach ($key in 'auto_index', 'auto_watch') {
            $value = @(Invoke-CodebaseMemoryCommand $Executable "codebase-memory-mcp $key query failed" @('config', 'get', $key)) | Select-Object -Last 1
            if (([string]$value).Trim() -cne 'true') { return $false }
        }
        return Test-CodebaseMemoryActivePath $ReleaseDir $ReleasesRoot $LegacyRoot
    } catch {
        return $false
    }
}

function Repair-CodebaseMemoryConfigDatabase($Path) {
    $Path = [IO.Path]::GetFullPath($Path)
    if (Test-CodebaseMemoryConfigDatabaseAccess $Path) { return }

    $escapedPath = $Path.Replace("'", "''")
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $takeown = (Join-Path $env:SystemRoot 'System32\takeown.exe').Replace("'", "''")
    $icacls = (Join-Path $env:SystemRoot 'System32\icacls.exe').Replace("'", "''")
    $command = @(
        "& '$takeown' /F '$escapedPath' | Out-Null"
        'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
        "& '$icacls' '$escapedPath' /reset /Q | Out-Null"
        'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
        "& '$icacls' '$escapedPath' /grant:r '*${sid}:(F)' /Q | Out-Null"
        'exit $LASTEXITCODE'
    ) -join '; '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $elevated = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-EncodedCommand', $encoded) -Verb RunAs -Wait -PassThru
    if ($elevated.ExitCode -ne 0 -or -not (Test-CodebaseMemoryConfigDatabaseAccess $Path)) {
        throw "Elevated codebase-memory config database ACL repair failed: $Path"
    }
}

function Invoke-CodebaseMemoryAgentInstall($Executable) {
    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE '.codex' } else { $env:CODEX_HOME }
    $codexConfig = Join-Path $codexHome 'config.toml'
    $toolApprovals = Suspend-CodebaseMemoryCodexToolApprovals $codexConfig
    try {
        Repair-CodebaseMemoryCodexMcp $codexConfig
        Repair-CodebaseMemoryCodexHooks $codexConfig
        Invoke-CodebaseMemoryCommand $Executable 'codebase-memory-mcp agent configuration failed' @('install', '-y', '--clients=codex')
    } finally {
        Restore-CodebaseMemoryCodexToolApprovals $codexConfig $toolApprovals
        Repair-CodebaseMemoryCodexHooks $codexConfig
        Remove-CodebaseMemoryPiSkill (Join-Path $env:USERPROFILE '.pi\agent\skills\codebase-memory')
        Remove-CodebaseMemoryPiAdapter (Join-Path $env:USERPROFILE '.pi\agent\extensions\cbmem.ts')
    }
}

function InstallCodebaseMemory {
    param([switch]$Update)
    Info "Installing codebase-memory-mcp..."
    if ($script:Dry) { return }
    if (-not [Environment]::Is64BitOperatingSystem) { throw "codebase-memory-mcp requires 64-bit Windows" }

    $pinsPath = Join-Path $script:DotfilesDir "packages\codebase-memory-mcp-release.json"
    if (-not (Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "Missing codebase-memory-mcp pin file: $pinsPath" }
    $pins = Get-Content -Raw -LiteralPath $pinsPath | ConvertFrom-Json
    $version = [string]$pins.version
    if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Invalid pinned codebase-memory-mcp version: $version" }
    $architecture = Get-CodebaseMemoryWindowsArch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
    $asset = $pins.windows.$architecture
    $expectedHash = [string]$asset.sha256
    $assetFile = [string]$asset.file
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') { throw "Invalid pinned codebase-memory-mcp checksum for $architecture" }
    if ($assetFile -notmatch "^codebase-memory-mcp(?:-ui)?-windows-$architecture\.zip$") { throw "Invalid pinned codebase-memory-mcp asset for $architecture" }

    $legacyRoot = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp"
    $releasesRoot = Join-Path $legacyRoot "releases"
    $releaseDir = Join-Path $releasesRoot "$version-windows-$architecture-$($expectedHash.Substring(0, 12))"
    $executable = Join-Path $releaseDir "codebase-memory-mcp.exe"
    New-Item -ItemType Directory -Force -Path $legacyRoot | Out-Null
    $installLock = [IO.File]::Open((Join-Path $legacyRoot "install.lock"), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

    try {
        if ((Test-Path -LiteralPath $releaseDir) -and -not (Test-CodebaseMemoryRelease $releaseDir $version)) {
            throw "Pinned codebase-memory-mcp release is incomplete: $releaseDir"
        }
        if (-not (Test-Path -LiteralPath $releaseDir)) {
            New-Item -ItemType Directory -Force -Path $releasesRoot | Out-Null
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) "codebase-memory-install-$([Guid]::NewGuid().ToString('N'))"
            $stagingDir = Join-Path $releasesRoot ".staging.$([Guid]::NewGuid().ToString('N'))"
            $archive = Join-Path $tempDir $assetFile
            $archiveLock = $null
            try {
                New-Item -ItemType Directory -Force -Path $tempDir, $stagingDir | Out-Null
                $uri = "https://github.com/DeusData/codebase-memory-mcp/releases/download/v$version/$assetFile"
                Invoke-WebRequest -Uri $uri -OutFile $archive -UseBasicParsing
                $archiveLock = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                if ((Get-StreamSha256 $archiveLock) -ne $expectedHash) { throw "codebase-memory-mcp package checksum mismatch" }
                if (-not (Test-CodebaseMemoryArchive $archive)) { throw "Unexpected codebase-memory-mcp archive layout" }
                Expand-Archive -LiteralPath $archive -DestinationPath $stagingDir -Force
                if (-not (Test-CodebaseMemoryRelease $stagingDir $version)) { throw "codebase-memory-mcp package is incomplete or has wrong version" }
                $archiveLock.Dispose()
                $archiveLock = $null
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction Stop
                Move-Item -LiteralPath $stagingDir -Destination $releaseDir
            } catch {
                $operationError = $_
                if ($archiveLock) { $archiveLock.Dispose(); $archiveLock = $null }
                $cleanupError = $null
                foreach ($path in $tempDir, $stagingDir) {
                    try {
                        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
                    } catch {
                        if (-not $cleanupError) { $cleanupError = $_.Exception }
                    }
                }
                if ($cleanupError) { throw "codebase-memory cleanup failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
                throw $operationError
            } finally {
                if ($archiveLock) { $archiveLock.Dispose() }
            }
        }

        if (-not (Test-CodebaseMemoryRelease $releaseDir $version)) { throw "Installed codebase-memory-mcp release verification failed" }
        $statePath = Join-Path $legacyRoot 'managed-state.json'
        $configDatabase = Join-Path $env:USERPROFILE '.cache\codebase-memory-mcp\_config.db'
        if (Test-CodebaseMemoryManagedState $statePath $version $releaseDir $executable $configDatabase $releasesRoot $legacyRoot) {
            Success "Finished installing codebase-memory-mcp"
            return
        }

        Invoke-CodebaseMemoryAgentInstall $executable
        Stop-CodebaseMemoryProcesses
        Repair-CodebaseMemoryConfigDatabase $configDatabase
        Invoke-CodebaseMemoryCommand $executable "codebase-memory-mcp auto-index configuration failed" @("config", "set", "auto_index", "true")
        Invoke-CodebaseMemoryCommand $executable "codebase-memory-mcp auto-watch configuration failed" @("config", "set", "auto_watch", "true")
        Set-CodebaseMemoryActivePath $releaseDir $releasesRoot $legacyRoot

        $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE '.codex' } else { $env:CODEX_HOME }
        $codexConfig = Join-Path $codexHome 'config.toml'
        if (Test-Path -LiteralPath $codexConfig -PathType Leaf) {
            $stateTemp = "$statePath.tmp.$([Guid]::NewGuid().ToString('N'))"
            try {
                @{
                    version = $version
                    releaseDir = $releaseDir
                    codexConfigSha256 = (Get-FileHash -LiteralPath $codexConfig -Algorithm SHA256).Hash
                } | ConvertTo-Json | Set-Content -LiteralPath $stateTemp -Encoding utf8
                Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $stateTemp -Destination $statePath
            } finally {
                Remove-Item -LiteralPath $stateTemp -Force -ErrorAction SilentlyContinue
            }
        }
    } finally {
        $installLock.Dispose()
    }

    Success "Finished installing codebase-memory-mcp"
}

function SyncAiInstructions {
    Info "Syncing shared agent instructions..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir 'config\shared\ai\AGENTS.md'
    $sourceSha256 = Get-FileSha256 $source
    foreach ($target in @(
            (Join-Path $env:USERPROFILE '.codex\AGENTS.md'),
            (Join-Path $env:USERPROFILE '.pi\agent\AGENTS.md')
        )) {
        $targetItem = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($targetItem -and -not $targetItem.PSIsContainer -and
            -not ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            $sourceSha256 -eq (Get-FileSha256 $target)) {
            continue
        }
        if ($targetItem -and ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Remove-Item -LiteralPath $target -Force
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

function Install-SkillDirectory($Source, $Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing vendored skill: $Source" }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'SKILL.md') -PathType Leaf)) { throw "Vendored skill has no SKILL.md: $Source" }
    $sourceItems = @((Get-Item -LiteralPath $Source -Force)) + @(Get-ChildItem -LiteralPath $Source -Recurse -Force)
    $sourceReparsePoint = $sourceItems | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    } | Select-Object -First 1
    if ($sourceReparsePoint) { throw "Vendored skill contains a reparse point: $($sourceReparsePoint.FullName)" }

    if (Test-Path -LiteralPath $Destination -PathType Container) {
        try {
            $targetItems = @((Get-Item -LiteralPath $Destination -Force)) + @(Get-ChildItem -LiteralPath $Destination -Recurse -Force)
            $targetReparsePoint = $targetItems | Where-Object {
                $_.Attributes -band [IO.FileAttributes]::ReparsePoint
            } | Select-Object -First 1
            $current = -not $targetReparsePoint -and $targetItems.Count -eq $sourceItems.Count
            foreach ($sourceItem in $sourceItems | Select-Object -Skip 1) {
                if (-not $current) { break }
                $relative = $sourceItem.FullName.Substring($sourceItems[0].FullName.Length + 1)
                $targetItem = Get-Item -LiteralPath (Join-Path $Destination $relative) -Force -ErrorAction Stop
                $current = $sourceItem.PSIsContainer -eq $targetItem.PSIsContainer
                if ($current -and -not $sourceItem.PSIsContainer) {
                    $current = $sourceItem.Length -eq $targetItem.Length -and
                        (Get-FileHash -LiteralPath $sourceItem.FullName -Algorithm SHA256).Hash -eq
                        (Get-FileHash -LiteralPath $targetItem.FullName -Algorithm SHA256).Hash
                }
            }
            if ($current) { return }
        } catch { }
    }

    $parent = Split-Path $Destination -Parent
    $name = Split-Path $Destination -Leaf
    $staging = Join-Path $parent ".$name.staging.$([Guid]::NewGuid().ToString('N'))"
    $backup = Join-Path $parent ".$name.backup.$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    try {
        Copy-Item -LiteralPath $Source -Destination $staging -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath (Join-Path $staging 'SKILL.md') -PathType Leaf)) { throw "Staged skill has no SKILL.md: $Source" }
        $reparsePoint = Get-ChildItem -LiteralPath $staging -Recurse -Force | Where-Object {
            $_.Attributes -band [IO.FileAttributes]::ReparsePoint
        } | Select-Object -First 1
        if ($reparsePoint) { throw "Vendored skill contains a reparse point: $($reparsePoint.FullName)" }

        if (Test-Path -LiteralPath $Destination) { Move-Item -LiteralPath $Destination -Destination $backup }
        Move-Item -LiteralPath $staging -Destination $Destination
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop }
    } catch {
        $operationError = $_
        $cleanupError = $null
        try {
            if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $backup) {
                if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction Stop }
                Move-Item -LiteralPath $backup -Destination $Destination -ErrorAction Stop
            }
        } catch {
            $cleanupError = $_.Exception
        }
        if ($cleanupError) { throw "Skill rollback failed after '$($operationError.Exception.Message)': $($cleanupError.Message)" }
        throw $operationError
    }
}

function InstallAiSkills {
    Info "Installing shared agent skills..."
    if ($script:Dry) { return }

    $sourceRoot = Join-Path $script:DotfilesDir 'config\shared\ai\skills'
    $targetRoot = Join-Path $env:USERPROFILE '.agents\skills'
    $skills = @('caveman', 'systematic-debugging', 'test-driven-development', 'verification-before-completion', 'diff-review-qa', 'efficient-subagent-use', 'ponytail', 'ponytail-audit', 'ponytail-debt', 'ponytail-gain', 'ponytail-help', 'ponytail-review')
    foreach ($skill in $skills) {
        Install-SkillDirectory (Join-Path $sourceRoot $skill) (Join-Path $targetRoot $skill)
        Remove-Item -LiteralPath (Join-Path $env:USERPROFILE ".pi\agent\skills\$skill") -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Install or update agent CLIs and their shared skills.
function InstallAi {
    param([switch]$Update)
    Info "Installing agent CLIs..."
    if ($script:Dry) { return }

    InstallFnm
    InstallCodex -Update:$Update

    InstallCodebaseMemory -Update:$Update
    InstallFffMcp -Update:$Update
    SyncCodexConfig
    InstallPi -Update:$Update
    InstallPiLanguageServers -Update:$Update
    InstallPiExtensions
    SyncPiConfigs
    if ($Update) {
        Invoke-NativeChecked "Pi extension reconciliation failed" { pi update --extensions }
    }
    SyncAiInstructions
    InstallAiSkills

    Success "Finished installing agent CLIs and skills"
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

function Sync-NeovimPlugins {
    Info "Installing or updating Neovim plugins and tools..."
    if ($script:Dry) { return }

    $nvim = Get-NeovimCommand
    if (-not $nvim) { throw "nvim executable not found" }
    $previousSync = $env:DOTFILE_NVIM_SYNC
    try {
        $env:DOTFILE_NVIM_SYNC = '0'
        $probe = (& $nvim --headless "+lua if require('config.sync').runtime_complete() then print('RAW_NEOVIM_SYNC_CURRENT') end" "+qa" 2>&1) -join "`n"
        $probeExitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousSync) {
            Remove-Item Env:DOTFILE_NVIM_SYNC -ErrorAction SilentlyContinue
        } else {
            $env:DOTFILE_NVIM_SYNC = $previousSync
        }
    }
    if ($probeExitCode -eq 0 -and $probe.Contains('RAW_NEOVIM_SYNC_CURRENT')) {
        Info "Neovim plugins and tools already current"
        return
    }

    try {
        $env:DOTFILE_NVIM_SYNC = '1'
        $output = (& $nvim --headless "+lua local sync = require('config.sync'); sync.plugins(false); sync.tools(); sync.parsers(); print('RAW_NEOVIM_SYNC_OK')" "+qa" 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousSync) {
            Remove-Item Env:DOTFILE_NVIM_SYNC -ErrorAction SilentlyContinue
        } else {
            $env:DOTFILE_NVIM_SYNC = $previousSync
        }
    }
    if ($output) { Write-Host $output }
    if ($exitCode -ne 0 -or -not $output.Contains('RAW_NEOVIM_SYNC_OK')) {
        throw "Neovim plugin or tool sync failed: $output"
    }

    $dataPath = Get-NeovimDataPath $nvim
    if (-not $dataPath) { throw "could not determine Neovim data path" }
    $lazyRoot = Join-Path $dataPath "lazy"
    if (-not (Test-Path -LiteralPath (Join-Path $lazyRoot "lazy.nvim")) -or
        -not (Test-Path -LiteralPath (Join-Path $lazyRoot "snacks.nvim"))) {
        throw "Neovim plugin sync did not install lazy.nvim and snacks.nvim"
    }
}

function Invoke-UpdatedDotfile($CommandName, $Target = '') {
    $scriptPath = Join-Path $script:DotfilesDir 'dotfile.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Updated dotfile script not found: $scriptPath" }
    $arguments = @('-NoProfile', '-File', $scriptPath, '-AfterUpdate')
    if ($script:Dry) { $arguments += '-Dry' }
    if ($script:Force) { $arguments += '-Force' }
    if ($script:Quiet) { $arguments += '-Quiet' }
    $arguments += $CommandName
    if ($Target) { $arguments += $Target }

    $previousSentinel = $env:DOTFILE_AFTER_UPDATE
    try {
        $env:DOTFILE_AFTER_UPDATE = '1'
        & (Get-Process -Id $PID).Path @arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($null -eq $previousSentinel) {
            Remove-Item Env:DOTFILE_AFTER_UPDATE -ErrorAction SilentlyContinue
        } else {
            $env:DOTFILE_AFTER_UPDATE = $previousSentinel
        }
    }
    if ($exitCode -ne 0) { throw "Updated dotfile process failed with exit code $exitCode" }
}

function Update-Packages($Target = '', [switch]$AfterRepoUpdate) {
    if ($Target -and $Target -ne 'ai') { Fail "Unknown update target: $Target" }
    $aiOnly = $Target -eq 'ai'
    Info $(if ($aiOnly) { "Updating AI tools and configs..." } else { "Updating packages..." })
    if (-not $AfterRepoUpdate) {
        UpdateRepo
        Invoke-UpdatedDotfile 'update' $Target
        return
    }

    if ($aiOnly) {
        InstallAi -Update
    } else {
        InstallPackages -Update
        InstallExtras -Update
        InstallAi -Update
        SetupSymlinks
        Sync-NeovimPlugins
    }
    if (-not $script:Dry) { Assert-WindowsHealthy }
    Success $(if ($aiOnly) { "Finished AI update" } else { "Finished updating packages" })
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

function New-LinkSpec($Kind, $Source, $Destination, [bool]$AddToPath = $false) {
    [pscustomobject]@{
        Kind = $Kind
        Source = $Source
        Destination = $Destination
        AddToPath = $AddToPath
    }
}

function Get-WindowsLinkSpecs {
    $configPath = Join-Path $script:DotfilesDir "config\windows"
    $sharedPath = Join-Path $script:DotfilesDir "config\shared"

    # Use $env:USERPROFILE rather than $HOME so test fixtures can override the
    # home directory by setting the env var. PowerShell's $HOME automatic
    # variable is read-only and frozen at session start, so $HOME would always
    # resolve to the real home - leaking test artifacts into ~/Documents etc.
    $userHome = $env:USERPROFILE
    $specs = @()

    # PowerShell profiles (link each file into the target dir).
    $psSource = Join-Path $configPath "Powershell"
    $targets = @(
        "$userHome\Documents\WindowsPowerShell"
        "$userHome\Documents\PowerShell"
    )
    foreach ($target in $targets) {
        Get-ChildItem $psSource -File | ForEach-Object {
            $specs += New-LinkSpec 'File' $_.FullName (Join-Path $target $_.Name)
        }
    }

    # Windows Terminal settings
    $specs += New-LinkSpec 'File' `
        (Join-Path $configPath "Terminal\settings.json") `
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

    # Git config
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".gitconfig") "$userHome\.gitconfig"
    $specs += New-LinkSpec 'File' (Join-Path $configPath ".gitconfig") "$userHome\.gitconfig.windows"

    # SSH and GnuPG configs
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath ".ssh\config") "$userHome\.ssh\config"
    $specs += New-LinkSpec 'File' (Join-Path $configPath ".gnupg\gpg-agent.conf") (Join-Path $env:APPDATA "gnupg\gpg-agent.conf")

    # Notepad++ settings: keep runtime-written config.xml writable.
    $notepadSource = Join-Path $configPath "Notepad++"
    $notepadTarget = Join-Path $env:APPDATA "Notepad++"
    foreach ($name in "contextMenu.xml", "shortcuts.xml") {
        $specs += New-LinkSpec 'File' (Join-Path $notepadSource $name) (Join-Path $notepadTarget $name)
    }
    Get-ChildItem (Join-Path $notepadSource "themes") -File | ForEach-Object {
        $specs += New-LinkSpec 'File' $_.FullName (Join-Path $notepadTarget "themes\$($_.Name)")
    }

    # Neovim settings: keep plugin manager state writable.
    $nvimSource = Join-Path $sharedPath "config\nvim"
    $nvimTarget = "$env:LOCALAPPDATA\nvim"
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "init.lua") (Join-Path $nvimTarget "init.lua")
    $specs += New-LinkSpec 'Dir' (Join-Path $nvimSource "lua") (Join-Path $nvimTarget "lua")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource ".gitignore") (Join-Path $nvimTarget ".gitignore")
    $specs += New-LinkSpec 'File' (Join-Path $nvimSource "stylua.toml") (Join-Path $nvimTarget "stylua.toml")

    # Jujutsu config (lives at %APPDATA%\jj\config.toml on Windows)
    $specs += New-LinkSpec 'Dir' (Join-Path $sharedPath "config\jj") "$env:APPDATA\jj"

    # starship prompt config - shared with zsh, read from ~/.config/starship.toml.
    $specs += New-LinkSpec 'File' (Join-Path $sharedPath "config\starship.toml") (Join-Path $userHome ".config\starship.toml")

    # Link the repo-root dotfile.ps1 entry point into a user PATH directory.
    $binDest = "$userHome\.local\bin"
    $specs += New-LinkSpec 'File' (Join-Path $script:DotfilesDir "dotfile.ps1") (Join-Path $binDest "dotfile.ps1") $true

    return $specs
}

function Sync-NotepadPlusPlusConfig {
    Info "Syncing writable Notepad++ configuration..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir "config\windows\Notepad++\config.xml"
    $target = Join-Path $env:APPDATA "Notepad++\config.xml"
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    (Get-Item -LiteralPath $target).IsReadOnly = $false
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

function Sync-LazyLock {
    Info "Syncing writable Neovim plugin lock..."
    if ($script:Dry) { return }

    $source = Join-Path $script:DotfilesDir "config\shared\config\nvim\lazy-lock.json"
    $target = "$env:LOCALAPPDATA\nvim\lazy-lock.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    $temporary = "$target.tmp.$([Guid]::NewGuid().ToString('N'))"
    try {
        Copy-Item -LiteralPath $source -Destination $temporary
        (Get-Item -LiteralPath $temporary).IsReadOnly = $false
        Move-Item -LiteralPath $temporary -Destination $target -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
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
    Sync-NotepadPlusPlusConfig
    Sync-LazyLock
    if (-not $script:Dry) {
        $gpgconf = Join-Path $env:ProgramFiles 'GnuPG\bin\gpgconf.exe'
        Invoke-NativeChecked "GPG agent reload failed" { & $gpgconf --reload gpg-agent }
    }

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
    $installedWinget = @{}
    foreach ($id in @(Get-InstalledWingetPackages)) { $installedWinget[[string]$id] = $true }
    foreach ($id in Get-WingetPackages) {
        if ($installedWinget.ContainsKey($id)) {
            Success "Winget package: $id"
        } else {
            FailSoft "Winget package missing: $id"
            $errors++
        }
    }

    Info "Verifying PowerShell modules..."
    if (Get-Module -ListAvailable -Name PSReadLine) {
        Success "PowerShell module: PSReadLine"
    } else {
        FailSoft "PowerShell module missing: PSReadLine"
        $errors++
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
    $callerPath = $env:Path
    try {
        Doctor
    } finally {
        $env:Path = $callerPath
    }
    if ($script:VerifyFailed) { throw "Windows installation verification failed" }
}

function SetupDotfiles([switch]$AfterRepoUpdate) {
    Info "Setting up dotfiles..."
    if (-not $AfterRepoUpdate) {
        UpdateRepo
        Invoke-UpdatedDotfile 'all'
        return
    }

    InstallManagedPackages
    SetupSymlinks
    Sync-NeovimPlugins
    if (-not $script:Dry) { Assert-WindowsHealthy }
    Success "Done!"
}

function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  update [ai] Update system packages
              Update only AI tools and configs with update ai
  packages    Install all managed packages only
  ai          Install AI tools and shared skills
  doctor      Detect Windows installation issues
  verify      Verify installation

Options:
  -d, --dry     Dry run (no changes made)
  -f, --force   Overwrite existing files without prompting
  -q, --quiet   Only show errors
  -h, --help    Show this help message
"@
}

if (-not $NoMain) {
    if ($AfterUpdate -and $env:DOTFILE_AFTER_UPDATE -ne '1') { Fail "-AfterUpdate is internal and requires the parent updater" }
    if ($Help) { ShowUsage; exit 0 }
    if ($UpdateTarget -and $Command -ne 'update') { Fail "Unexpected argument after ${Command}: $UpdateTarget" }

    switch ($Command) {
        "all"       { SetupDotfiles -AfterRepoUpdate:$AfterUpdate }
        "update"    { Update-Packages $UpdateTarget -AfterRepoUpdate:$AfterUpdate }
        "packages"  { InstallManagedPackages }
        "ai"        { InstallAi }
        "doctor"    { Doctor; if ($script:VerifyFailed) { exit 1 } }
        "verify"    { Verify; if ($script:VerifyFailed) { exit 1 } }
        default     { Fail "Unknown command: $Command" }
    }
}
