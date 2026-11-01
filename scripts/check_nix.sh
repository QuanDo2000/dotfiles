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
    local username shared_status
    username="$(nix eval --raw --file "$repo_dir/config/host.nix" username)"
    if [[ -n "${TEST_JOBS_SHARED_DIR:-}" && "${TEST_JOBS_SHARED_ROLE:-}" == 2 ]]; then
      if bash "$repo_dir/scripts/check_profile.sh" --platform-observations read "$repo_dir" "$username"; then
        return 0
      else
        shared_status=$?
        [[ "$shared_status" == 3 ]] || return "$shared_status"
      fi
    fi
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

check_status() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    local status_package
    status_package=$(nix build "$flake#hyprsunset-status" --no-link --print-out-paths)
    HYPRSUNSET_CANDIDATE="$status_package/bin/hyprsunset-status" run python3 "$repo_dir/tests/rust/hyprsunset_oracle.py"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "$stage_dir"' EXIT
  stages=()
  # Independent checks share Nix's native store; Linux raw drv observations
  # may use validated fresh Home data. Build/oracle dependencies stay internal.
  for stage in check_flake check_platform check_packages check_status; do
    printf 'source %q\n%s\n' "$repo_dir/scripts/check_nix.sh" "$stage" > "$stage_dir/$stage.sh"
    stages+=("$stage_dir/$stage.sh")
  done
  python3 "$repo_dir/scripts/test_jobs.py" --jobs 3 --cleanup-seconds 1 --timeout 10800 --total-timeout 10803 \
    --files "${stages[@]}" -- bash
fi
