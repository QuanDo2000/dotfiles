#!/usr/bin/env bash
# Internal Unix gate stage; scripts/check.sh supervises its deadline/cleanup.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flake="path:$repo_dir"
cd "$repo_dir"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

check_flake() {
  run nix flake check "$flake" --no-build --all-systems
}

check_platform() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    run nix eval --raw "$flake#darwinConfigurations.mac.system.drvPath"
    run nix build "$flake#rex" --no-link
  else
    local username
    username="$(nix eval --raw --file "$repo_dir/config/host.nix" username)"
    run nix eval --raw "$flake#homeConfigurations.\"$username@linux\".activationPackage.drvPath"
    run nix eval --raw "$flake#homeConfigurations.\"$username@arch-server\".activationPackage.drvPath"
  fi
}

check_packages() {
  local packages=("$flake#pi-extensions")
  if [[ "$(uname -s)" == "Linux" ]]; then
    packages+=("$flake#obsidian-headless" "$flake#pi-agent" "$flake#rex")
  fi
  run nix build "${packages[@]}" --no-link
}

check_deployed_role() {
  [[ "${DOTFILE_CHECK_DEPLOYED_ROLE:-}" == 1 ]] || return 0
  # shellcheck source=platform.sh
  source "$repo_dir/scripts/platform.sh"
  local target host username platform
  platform="$(detect_platform)"
  case "$platform" in
    nixos)
      host="$(nix eval --raw --file "$repo_dir/config/host.nix" hostName)"
      is_wsl && host="${host}-wsl"
      target="nixosConfigurations.\"$host\".config.system.build.toplevel.drvPath" ;;
    mac) target='darwinConfigurations.mac.system.drvPath' ;;
    debian|arch)
      username="$(nix eval --raw --file "$repo_dir/config/host.nix" username)"
      if [[ "$platform" == arch ]]; then
        target="homeConfigurations.\"$username@arch-server\".activationPackage.drvPath"
      else
        target="homeConfigurations.\"$username@linux\".activationPackage.drvPath"
      fi ;;
    *) printf 'Unsupported update platform\n' >&2; return 1 ;;
  esac
  run nix eval --raw "$flake#$target"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "$stage_dir"' EXIT
  stages=()
  # Independent checks share Nix's native store.
  for stage in check_flake check_platform check_packages check_deployed_role; do
    printf 'source %q\n%s\n' "$repo_dir/scripts/check_nix.sh" "$stage" > "$stage_dir/$stage.sh"
    stages+=("$stage_dir/$stage.sh")
  done
  python3 "$repo_dir/scripts/test_jobs.py" --jobs 3 --cleanup-seconds 1 --timeout 10800 --total-timeout 10803 \
    --files "${stages[@]}" -- bash
fi
