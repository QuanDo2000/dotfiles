# Local
[ -e "$HOME/.zshrc.local" ] && source $HOME/.zshrc.local

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export GOPATH=/usr/local/go
if [[ -e "$GOPATH" ]]; then
  export GOBIN=$GOPATH/bin
  export PATH=$PATH:$GOBIN
fi
