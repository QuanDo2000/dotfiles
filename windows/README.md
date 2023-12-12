# dotfiles for Windows

## Installation

- The Windows installation still contains some bugs and is not fully tested.
- Run the following in PowerShell as Administrator.

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process
iwr -useb https://raw.githubusercontent.com/QuanDo2000/monorepo/main/dotfiles/install.ps1 | iex
```

## Notes

- For the Windows installation, there is a repeat for the vimrc file because the path where vim-plug is installed is different.
