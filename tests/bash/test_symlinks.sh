#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh symlinks.sh
}

teardown() {
  cleanup_test_env
}

test_setup_symlinks_is_home_manager_noop() {
  create_dotfiles_dirs
  mkdir -p "$DOTFILES_DIR/config/shared/config"
  echo "git" > "$DOTFILES_DIR/config/shared/.gitconfig"
  echo "format = \"\$character\"" > "$DOTFILES_DIR/config/shared/config/starship.toml"
  echo "#!/usr/bin/env bash" > "$DOTFILES_DIR/dotfile"

  local output
  output="$(setup_symlinks 2>&1)"

  assert_contains "$output" "Home Manager manages dotfile links"
  for path in "$HOME/.gitconfig" "$HOME/.config/starship.toml" "$HOME/.local/bin/dotfile" "$HOME/.zshrc"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      echo "  FAILED: $path should be left for Home Manager" >> "$ERROR_FILE"
    fi
  done
}

test_setup_symlinks_dry_run_creates_nothing() {
  DRY=true
  create_dotfiles_dirs

  setup_symlinks >/dev/null

  if [ -e "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ]; then
    echo "  FAILED: dry run should not create ~/.zshrc" >> "$ERROR_FILE"
  fi
}
