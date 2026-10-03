#!/usr/bin/env bash
# Called inside the pinned update environment, before activation/publication.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
scope="${1:-full}"
base="${2:-HEAD}"
[[ $# -le 2 && "$scope" =~ ^(full|ai)$ ]] || { echo 'Usage: check-update.sh [full|ai] [base revision]' >&2; exit 1; }
git rev-parse --verify "$base^{commit}" >/dev/null 2>&1 || { echo 'Invalid update base revision' >&2; exit 1; }

# Only pin surfaces use the focused gate. Wiring/code changes retain full checks.
# Include untracked inputs and committed updates after a publication rebase.
changes="$(git diff --name-only --no-renames "$base" --)"
untracked="$(git ls-files --others --exclude-standard)"
changes="${changes}${changes:+$'\n'}$untracked"
pi=false extensions=false obsidian=false neovim=false flake_changed=false
while IFS= read -r path; do
  case "$path" in
    '') ;;
    flake.lock) pi=true extensions=true obsidian=true neovim=true flake_changed=true ;;
    packages/pi-agent.nix|packages/pi-agent-npm-shrinkwrap.json) pi=true ;;
    packages/pi-extensions.nix|packages/pi-extensions-release.json|config/shared/ai/pi/extensions/package.json|config/shared/ai/pi/extensions/package-lock.json|config/shared/ai/pi/settings.json) extensions=true ;;
    packages/obsidian-headless.nix|packages/obsidian-headless-package-lock.json) obsidian=true ;;
    config/shared/config/nvim/lazy-lock.json|config/shared/config/nvim/mason-tools.json) neovim=true ;;
    packages/webcord-release.nix|config/windows/anki-addons.json|config/shared/ai/skills/*) ;;
    *) exec bash "$repo_dir/scripts/check.sh" ;;
  esac
done <<< "$changes"
# AI refreshes must never silently validate non-AI pin changes as AI-only.
if [[ "$scope" == ai ]] && { $flake_changed || $obsidian || $neovim; }; then
  exec bash "$repo_dir/scripts/check.sh"
fi

tests=(test_update_packages.sh test_release_pins.sh test_config_merge.sh)
if $pi || $extensions; then tests+=(test_pi_extensions.sh test_pi_compaction_patch.sh); fi
if $neovim; then tests+=(test_neovim.sh test_pins.sh); fi
if $flake_changed; then tests+=(test_home_profiles.sh); fi
bash "$repo_dir/tests/bash/runner.sh" "${tests[@]}"

# Evaluate the deployed role, not an inferred generic Linux target.
source "$repo_dir/scripts/platform.sh"
flake="path:$repo_dir"
case "$(detect_platform)" in
  nixos)
    host="$(nix eval --raw --file "$repo_dir/config/host.nix" hostName)"
    is_wsl && host="${host}-wsl"
    target="nixosConfigurations.\"$host\".config.system.build.toplevel.drvPath" ;;
  mac) target='darwinConfigurations.mac.system.drvPath' ;;
  debian|arch)
    username="$(nix eval --raw --file "$repo_dir/config/host.nix" username)"
    profile=linux
    [[ "$(detect_platform)" != arch ]] || profile=arch-server
    target="homeConfigurations.\"$username@$profile\".activationPackage.drvPath" ;;
  *) echo 'Unsupported update platform' >&2; exit 1 ;;
esac
nix eval --raw "$flake#$target"
packages=()
# The extension install check starts the actual pinned Pi CLI offline.
if $pi || $extensions; then packages+=("$flake#pi-extensions"); fi
if [[ "$(uname -s)" == Linux ]]; then
  if $pi; then packages+=("$flake#pi-agent"); fi
  if $obsidian; then packages+=("$flake#obsidian-headless"); fi
fi
if [[ ${#packages[@]} -gt 0 ]]; then nix build "${packages[@]}" --no-link; fi
if $flake_changed && [[ "$(uname -s)" == Linux ]]; then
  status_package="$(nix build "$flake#hyprsunset-status" --no-link --print-out-paths)"
  HYPRSUNSET_CANDIDATE="$status_package/bin/hyprsunset-status" python3 "$repo_dir/tests/rust/hyprsunset_oracle.py"
fi
