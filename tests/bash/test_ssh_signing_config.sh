#!/usr/bin/env bash
# Native config consumption only: no keys, signing, or crypto-proof claims.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
}

teardown() {
  cleanup_test_env
}

signing_env() {
  if [[ "$1" == git && "$2" == config ]]; then
    shift 2
    set -- git config --includes "$@"
  fi
  env -i PATH="$PATH" HOME="$HOME" USERPROFILE="$HOME" \
    XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" \
    APPDATA="$HOME/.config" GIT_CONFIG_NOSYSTEM=1 "$@"
}

test_git_ssh_defaults_and_local_override() {
  cp "$REPO_DIR/config/shared/.gitconfig" "$HOME/.gitconfig"
  cp "$REPO_DIR/config/windows/.gitconfig" "$HOME/.gitconfig.windows"
  local value
  value="$(signing_env git config --global --get gpg.format)"
  assert_equals ssh "$value"
  value="$(signing_env git config --global --get user.signingkey)"
  assert_equals '~/.ssh/id_ed25519.pub' "$value"
  value="$(signing_env git config --global --path --get user.signingkey)"
  assert_equals "$HOME/.ssh/id_ed25519.pub" "$value"
  value="$(signing_env git config --global --bool --get commit.gpgsign)"
  assert_equals true "$value"
  value="$(signing_env git config --global --bool --get tag.gpgsign)"
  assert_equals true "$value"
  value="$(signing_env git config --global --bool --get windows.appendAtomically)"
  assert_equals false "$value"
  assert_exit_code 1 signing_env git config --global --get gpg.program
  signing_env git config --file "$HOME/.gitconfig.local" user.signingkey '~/.ssh/approved-override.pub'
  signing_env git config --file "$HOME/.gitconfig.local" windows.appendAtomically true
  value="$(signing_env git config --global --get user.signingkey)"
  assert_equals '~/.ssh/approved-override.pub' "$value"
  value="$(signing_env git config --global --bool --get windows.appendAtomically)"
  assert_equals true "$value"
  signing_env git config --file "$HOME/.gitconfig.local" gpg.format openpgp
  value="$(signing_env git config --global --get gpg.format)"
  assert_equals openpgp "$value"
}

test_jj_native_defaults_and_override_precedence() {
  mkdir -p "$HOME/.config/jj/conf.d"
  cp "$REPO_DIR/config/shared/config/jj/config.toml" "$HOME/.config/jj/config.toml"
  local value
  value="$(cd "$HOME" && signing_env jj config get signing.backend)"
  assert_equals ssh "$value"
  value="$(cd "$HOME" && signing_env jj config get signing.key)"
  assert_equals '~/.ssh/id_ed25519.pub' "$value"
  value="$(cd "$HOME" && signing_env jj config get signing.behavior)"
  assert_equals own "$value"
  printf '[signing]\nbehavior = "keep"\nkey = "~/.ssh/approved-override.pub"\n' > "$HOME/.config/jj/conf.d/99-local.toml"
  value="$(cd "$HOME" && signing_env jj config get signing.behavior)"
  assert_equals keep "$value"
  value="$(cd "$HOME" && signing_env jj config get signing.key)"
  assert_equals '~/.ssh/approved-override.pub' "$value"
  # Empty disposable repository: no commit or signing operation.
  (cd "$HOME" && signing_env jj git init repo)
  (cd "$HOME/repo" && signing_env jj config set --repo signing.key '~/.ssh/repo-override.pub')
  value="$(cd "$HOME/repo" && signing_env jj config get signing.key)"
  assert_equals '~/.ssh/repo-override.pub' "$value"
  value="$(cd "$HOME/repo" && signing_env jj config get signing.backend)"
  assert_equals ssh "$value"
}
