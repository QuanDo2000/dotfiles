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

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

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
