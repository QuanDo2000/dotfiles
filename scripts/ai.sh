#!/bin/bash
set -eo pipefail

function install_opencode {
  if command -v opencode &>/dev/null; then
    info "OpenCode $(opencode --version) already installed"
    return
  fi

  info "Installing OpenCode..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: curl -fsSL https://opencode.ai/install | bash"
  else
    curl -fsSL https://opencode.ai/install | bash \
      || fail "OpenCode installation failed"
  fi
  success "Finished installing OpenCode"
}

function install_bun {
  setup_bun
}

function install_claude_code {
  if command -v claude &>/dev/null; then
    info "Claude Code $(claude --version 2>/dev/null || echo 'installed') already installed"
    return
  fi

  info "Installing Claude Code..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: curl -fsSL https://claude.ai/install.sh | bash"
  else
    curl -fsSL https://claude.ai/install.sh | bash \
      || fail "Claude Code installation failed"
  fi
  success "Finished installing Claude Code"
}

function install_codex {
  if command -v codex &>/dev/null; then
    info "Codex $(codex --version 2>/dev/null || echo 'installed') already installed"
    return
  fi

  install_bun

  info "Installing Codex..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: bun install -g @openai/codex"
  else
    bun install -g @openai/codex \
      || fail "Codex installation failed"
  fi
  success "Finished installing Codex"
}

function install_ai {
  install_opencode
  install_claude_code
  install_codex
}
