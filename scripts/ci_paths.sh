#!/usr/bin/env bash
set -eu

linux=false
macos=false
windows=false
nix=false

while IFS= read -r path; do
  case "$path" in
    .github/workflows/* | .gitattributes | AGENTS.md | README.md | dotfile | dotfile.ps1 | flake.nix | flake.lock | packages/* | scripts/* | tests/bash/* | tests/nix/* | tests/nvim/* | config/*)
      linux=true
      ;;
  esac

  case "$path" in
    .github/workflows/* | .gitattributes | AGENTS.md | README.md | dotfile | flake.nix | flake.lock | packages/* | scripts/* | tests/bash/helpers.sh | tests/bash/runner.sh | tests/bash/test_ci.sh | tests/bash/test_cli.sh | tests/bash/test_doctor.sh | tests/bash/test_mac_install.sh | tests/bash/test_neovim.sh | tests/bash/test_tmux.sh | tests/nvim/* | config/darwin.nix | config/home.nix | config/host.nix | config/shared/* | config/unix/* | config/mac/*)
      macos=true
      ;;
  esac

  case "$path" in
    .github/workflows/* | .gitattributes | README.md | dotfile.ps1 | packages/* | scripts/* | tests/powershell/* | tests/nvim/* | config/shared/* | config/windows/*)
      windows=true
      ;;
  esac

  case "$path" in
    .github/workflows/* | .gitattributes | dotfile | flake.nix | flake.lock | packages/* | scripts/* | tests/nix/* | config/arch-server/* | config/darwin.nix | config/home.nix | config/host.nix | config/hardware-configuration.nix | config/shared/* | config/unix/* | config/mac/* | config/nixos/* | config/nixos-wsl/*)
      nix=true
      ;;
  esac
done

printf 'linux=%s\nmacos=%s\nwindows=%s\nnix=%s\n' "$linux" "$macos" "$windows" "$nix"
