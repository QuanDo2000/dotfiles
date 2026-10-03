#!/usr/bin/env bash
set -eu

linux=false
macos=false
windows=false
nix=false

while IFS= read -r path; do
  # Narrow only known ownership. Unknown scripts/packages retain all platforms.
  case "$path" in
    packages/hyprsunset-status.nix | packages/obsidian-headless* | packages/webcord-release.nix | scripts/google-drive-storage-sync.py | scripts/hyprsunset-status.sh | scripts/input-method-status.sh | scripts/show-keybinds.sh | rust/* | tests/rust/* | config/unix/config/hypr/* | config/unix/config/waybar/* | config/unix/config/fcitx5/*)
      linux=true
      nix=true
      continue
      ;;
    packages/pi-extensions.nix | scripts/apply_hermes_skill_fixes.sh | scripts/check.sh | scripts/check-update.sh | scripts/doctor.sh | scripts/host_config.sh | scripts/obsidian.sh | scripts/packages.sh | scripts/pins.sh | scripts/platform.sh | scripts/releases.sh | scripts/update_pins.py | scripts/utils.sh | tests/ai/pi-web-activation-smoke.mjs)
      linux=true
      macos=true
      nix=true
      continue
      ;;
  esac

  case "$path" in
    .github/workflows/* | .gitattributes | AGENTS.md | README.md | dotfile | dotfile.ps1 | flake.nix | flake.lock | packages/* | scripts/* | tests/bash/* | tests/nix/* | tests/nvim/* | config/*)
      linux=true
      ;;
  esac

  case "$path" in
    .github/workflows/* | .gitattributes | AGENTS.md | README.md | dotfile | flake.nix | flake.lock | packages/* | scripts/* | tests/bash/helpers.sh | tests/bash/runner.sh | tests/bash/test_ci.sh | tests/bash/test_cli.sh | tests/bash/test_doctor.sh | tests/bash/test_mac_install.sh | tests/bash/test_neovim.sh | tests/bash/test_tmux.sh | tests/bash/test_release_pins.sh | tests/nvim/* | config/darwin.nix | config/home.nix | config/host.nix | config/shared/* | config/unix/* | config/mac/*)
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
