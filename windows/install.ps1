function CopyWithBackup($source, $destination) {
    if (!(Test-Path $destination)) {
        Copy-Item -Path $source -Destination $destination
    }
    else {
        Copy-Item -Path $destination -Destination "$destination.bak"
        Copy-Item -Path $source -Destination $destination -Force
    }
}

function CopyDirWithBackup($source, $destination) {
    if (!(Test-Path $destination)) {
        Copy-Item -Path $source -Destination $destination -Recurse
    }
    else {
        Copy-Item -Path $destination -Destination "$destination.bak" -Recurse -Force
        Copy-Item -Path $source -Destination $destination -Force -Recurse
    }
}

function RunMSYS2($command) {
    C:\msys64\usr\bin\bash -l -c $command
}

function SetupMSYS2() {
    $env:PATH += ";C:\msys64\usr\bin"
    pacman -S mingw-w64-ucrt-x86_64-gcc zsh git vim tmux mingw-w64-ucrt-x86_64-ttf-firacode-nerd mingw-w64-ucrt-x86_64-fzf mingw-w64-ucrt-x86_64-ripgrep --noconfirm
    pacman -Suy --noconfirm
    RunMSYS2 -command "/c/Users/Quan/Documents/Projects/dotfiles/unix/install"
}

function InstallPackages() {
    winget install Microsoft.Powershell Git.Git Microsoft.VisualStudioCode Microsoft.WindowsTerminal JanDeDobbeleer.OhMyPosh MSYS2.MSYS2 --disable-interactivity --accept-package-agreements

    Update-Module
    SetupMSYS2

    $scoopExists = [Boolean](Get-Command scoop -ErrorAction SilentlyContinue)
    if (-Not $scoopExists) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    }
}

function InstallFont {
    # $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
    Write-Host "Installing FiraCode using scoop..."
    scoop bucket add nerd-fonts
    scoop install FiraCode
    scoop update FiraCode
    Write-Host "Done."
}

function CloneRepo() {
    $repo = "https://github.com/QuanDo2000/dotfiles.git"
    $destination = "$HOME\Documents\Projects\dotfiles"
    Write-Host "Cloning $repo to $destination..."

    if (!(Test-Path $destination)) {
        git clone $repo $destination
    }
    else {
        git -C $destination pull
    }
    Write-Host "Done."
}

function SyncSettings() {
    Write-Host "Syncing settings..."
    $configPath = "$HOME\Documents\Projects\dotfiles\windows"

    $targets = @(
        "$HOME\Documents\WindowsPowerShell"
        "$HOME\Documents\PowerShell"
    )

    foreach ($target in $targets) {
        if (!(Test-Path $target)) {
            New-Item -ItemType Directory -Path $target
        }
    }

    foreach ($target in $targets) {
        Write-Host "Syncing to $target..."
        CopyDirWithBackup -source "$configPath\Powershell\*" -destination $target
    }

    Write-Host "Syncing Terminal settings..."
    $terminalSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $terminalSettingsSource = "$configPath\Terminal\settings.json"
    CopyWithBackup -source $terminalSettingsSource -destination $terminalSettingsPath

    Write-Host "Syncing Vim settings..."
    CopyWithBackup -source "$configPath\_vimrc" -destination "$HOME\_vimrc"
    CopyWithBackup -source "$configPath\_gvimrc" -destination "$HOME\_gvimrc"
    CopyWithBackup -source "$configPath\.gitconfig" -destination "$HOME\.gitconfig"

    Write-Host "Done."
}

InstallPackages
InstallFont
CloneRepo
SyncSettings
