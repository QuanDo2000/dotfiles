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

# nvm — lazy-loaded. Sourcing nvm.sh eagerly costs ~750ms per shell (nvm_auto
# resolves the default Node version on every startup). Instead, install shims
# that source nvm on the first call to nvm/node/npm/npx, then hand off. Trade-off:
# automatic .nvmrc switching on shell start is lost; it resumes after first use.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  _load_nvm() {
    unset -f nvm node npm npx 2>/dev/null
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  }
  for _cmd in nvm node npm npx; do
    eval "${_cmd}() { _load_nvm; ${_cmd} \"\$@\"; }"
  done
  unset _cmd
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
