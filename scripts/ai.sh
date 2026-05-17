#!/bin/bash
set -eo pipefail

# Default subscription flags (override via environment)
OMO_CLAUDE="${OMO_CLAUDE:-no}"
OMO_OPENAI="${OMO_OPENAI:-yes}"
OMO_GEMINI="${OMO_GEMINI:-no}"
OMO_COPILOT="${OMO_COPILOT:-no}"
OMO_OPENCODE_ZEN="${OMO_OPENCODE_ZEN:-yes}"
OMO_OPENCODE_GO="${OMO_OPENCODE_GO:-yes}"
OMO_ZAI="${OMO_ZAI:-no}"
OMO_KIMI="${OMO_KIMI:-no}"
OMO_VERCEL="${OMO_VERCEL:-no}"

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
  if command -v bun &>/dev/null; then
    info "bun $(bun --version) already installed"
    return
  fi

  info "Installing bun..."
  if [[ "$DRY" == "true" ]]; then
    info "Would run: curl -fsSL https://bun.sh/install | bash"
  else
    curl -fsSL https://bun.sh/install | bash \
      || fail "bun installation failed"
    export PATH="$HOME/.bun/bin:$PATH"
  fi
  success "Finished installing bun"
}

function install_oh_my_openagent {
  install_bun

  info "Installing oh-my-openagent..."

  if [[ "$DRY" == "true" ]]; then
    info "Would run: bunx oh-my-openagent install --no-tui --claude=$OMO_CLAUDE --openai=$OMO_OPENAI --gemini=$OMO_GEMINI --copilot=$OMO_COPILOT --opencode-zen=$OMO_OPENCODE_ZEN --opencode-go=$OMO_OPENCODE_GO --zai-coding-plan=$OMO_ZAI --kimi-for-coding=$OMO_KIMI --vercel-ai-gateway=$OMO_VERCEL"
  else
    bunx oh-my-openagent install --no-tui \
      --claude="$OMO_CLAUDE" \
      --openai="$OMO_OPENAI" \
      --gemini="$OMO_GEMINI" \
      --copilot="$OMO_COPILOT" \
      --opencode-zen="$OMO_OPENCODE_ZEN" \
      --opencode-go="$OMO_OPENCODE_GO" \
      --zai-coding-plan="$OMO_ZAI" \
      --kimi-for-coding="$OMO_KIMI" \
      --vercel-ai-gateway="$OMO_VERCEL" \
      || fail "oh-my-openagent install failed"

    info "Running oh-my-openagent doctor..."
    bunx oh-my-openagent doctor || fail_soft "oh-my-openagent doctor reported issues"
  fi

  success "Finished installing oh-my-openagent"
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

function install_ai {
  install_opencode
  install_claude_code
  install_oh_my_openagent
}
