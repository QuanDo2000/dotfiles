# Base config (tracked in dotfiles repo)
[ -e "$HOME/.zshrc.base" ] && source $HOME/.zshrc.base

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

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
