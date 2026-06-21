# Base config (tracked in dotfiles repo)
[ -e "$HOME/.zshrc.base" ] && source "$HOME/.zshrc.base"

# jj (jujutsu) completion — dynamic mode, requires compinit (set up in .zshrc.base).
command -v jj >/dev/null 2>&1 && source <(COMPLETE=zsh jj)

# Go
export GOPATH="$HOME/.local/go"
if [[ -e "$GOPATH" ]]; then
  export GOBIN=$GOPATH/bin
  export PATH=$PATH:$GOBIN
fi

# nvm — lazy-loaded for speed. Sourcing nvm.sh eagerly costs ~750ms per shell
# (nvm_auto resolves the default Node version on every startup). But node/npm/npx
# and globally-installed CLIs must stay on PATH for NON-interactive consumers
# (Makefiles, git hooks, editor subprocesses) that never trigger a shell function.
# So: add the default Node version's bin dir to PATH eagerly (cheap, no nvm.sh
# source), and lazy-load full nvm only for `nvm` management commands.
# Trade-off: automatic .nvmrc switching on shell start is lost; it resumes the
# first time `nvm`/`nvm use` runs in a session.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # Resolve the default Node version's bin dir without sourcing nvm.
  _nvm_default=$( [ -r "$NVM_DIR/alias/default" ] && cat "$NVM_DIR/alias/default" )
  _nvm_bin=""
  case "$_nvm_default" in
    v*) [ -d "$NVM_DIR/versions/node/$_nvm_default/bin" ] \
          && _nvm_bin="$NVM_DIR/versions/node/$_nvm_default/bin" ;;
  esac
  # Non-concrete alias (node/stable/lts/*) or unresolved → newest installed version.
  [ -n "$_nvm_bin" ] || _nvm_bin=$(find "$NVM_DIR/versions/node" -mindepth 2 -maxdepth 2 \
    -type d -name bin 2>/dev/null | sort -V | tail -n1)
  [ -n "$_nvm_bin" ] && [ -d "$_nvm_bin" ] && PATH="$_nvm_bin:$PATH"
  unset _nvm_default _nvm_bin

  # Lazy-load full nvm (management commands) on first use, then hand off.
  nvm() {
    unset -f nvm
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    nvm "$@"
  }
fi

# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# bun
[ -d "$HOME/.bun/bin" ] && export PATH="$HOME/.bun/bin:$PATH"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# zoxide — initialized last (after all other PATH/config) so its `cd` override and
# chpwd hook aren't clobbered by anything sourced later, and to satisfy zoxide's
# own "init at end of config" guidance. Replaces the omz zoxide plugin + ZOXIDE_CMD_OVERRIDE.
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --cmd cd)"
