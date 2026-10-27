#!/usr/bin/env bash
# Requires an installed Rex CLI/server, Neovim and jq; never targets the live server.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for tool in rex nvim zsh jq; do command -v "$tool" >/dev/null; done
scratch="$(mktemp -d "${TMPDIR:?Set TMPDIR to a writable scratch directory}/rex-work-smoke.XXXXXX")"
export DOTFILES_DIR="$repo"
export XDG_RUNTIME_DIR="$scratch/runtime"
export REX_SERVER="unix://$scratch/not-the-local-server.sock"
case "$(uname -s)" in
  Darwin)
    export HOME="$scratch/home"
    endpoint="unix://$HOME/Library/Application Support/rex/server.sock"
    ;;
  Linux) endpoint="unix://$XDG_RUNTIME_DIR/rex/server.sock" ;;
  *) printf 'Unsupported platform\n' >&2; exit 1 ;;
esac
mkdir -p "$(dirname "${endpoint#unix://}")"
started=false
cleanup() {
  local status=$?
  if [[ "$started" == true ]]; then
    if ! rex -S "$endpoint" --autostart=false --timeout 5s server stop; then
      printf 'Cleanup failed; isolated server state retained at %s\n' "$scratch" >&2
      exit 1
    fi
    if rex -S "$endpoint" --autostart=false --timeout 2s server status >/dev/null 2>&1; then
      printf 'Isolated server still running: %s\n' "$scratch" >&2
      exit 1
    fi
  fi
  rm -rf -- "$scratch"
  exit "$status"
}
trap cleanup EXIT
bash "$repo/dotfile" -d rex-work
if bash "$repo/dotfile" rex-work >"$scratch/missing-server.log" 2>&1; then
  printf 'Launcher unexpectedly started a missing server\n' >&2; exit 1
fi
started=true
rex -S "$endpoint" server start --state-dir "$scratch/server" --config /dev/null \
  --max-sessions 4 --max-blocks 16 >/dev/null
bash "$repo/dotfile" rex-work >"$scratch/created.json"
session="$(jq -er '.session_id' "$scratch/created.json")"
rex -S "$endpoint" block ls -s "$session" --json >"$scratch/blocks.json"
jq -e '([.blocks[].label] | sort) == ["Checks", "Editor", "Shell"]' "$scratch/blocks.json" >/dev/null
# Inspect only processes in the session this test created, never terminal history.
while IFS=$'\t' read -r block label; do
  expected=zsh
  [[ "$label" == Editor ]] && expected=nvim
  ready=false
  for ((attempt=0; attempt<30; attempt++)); do
    rex -S "$endpoint" --timeout 2s block call -s "$session" -b "$block" process >"$scratch/process.json"
    if jq -e --arg cwd "$repo" --arg name "$expected" \
      '.foreground.cwd == $cwd and .foreground.name == $name' "$scratch/process.json" >/dev/null; then
      ready=true; break
    fi
    sleep 0.2
  done
  [[ "$ready" == true ]] || { printf 'Unexpected process in %s\n' "$label" >&2; exit 1; }
done < <(jq -r '.blocks[] | [.block_id, .label] | @tsv' "$scratch/blocks.json")
if bash "$repo/dotfile" rex-work >"$scratch/duplicate.log" 2>&1; then
  printf 'Duplicate launcher unexpectedly succeeded\n' >&2; exit 1
fi
rex -S "$endpoint" ls --json | jq -e '.sessions | length == 1' >/dev/null
printf 'PASS: dry run, missing-server refusal, three live processes/cwds, duplicate guard\n'
