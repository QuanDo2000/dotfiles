#!/bin/bash
set -eo pipefail

# AI coding assistants. The actual installers live in packages.sh
# (setup_opencode, setup_codex) so the main `dotfile all` run and the
# standalone `dotfile ai` subcommand share one code path.
function install_ai {
  setup_opencode
  setup_codex
}
