#!/usr/bin/env bash
# Cross-platform tmux configuration tests.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() { init_test_env; }
teardown() { cleanup_test_env; }

test_tmux_avoids_recurring_identity_process() {
  local tmux_config
  tmux_config="$(<"$REPO_DIR/config/unix/.tmux.conf")"
  assert_contains "$tmux_config" '#{E:USER}'
  assert_not_contains "$tmux_config" '#(whoami)'
}

test_tmux_uses_native_clipboard_bindings_without_yank_plugin() {
  local tmux_config
  tmux_config="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_contains "$tmux_config" 'set -g set-clipboard on'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi Y send-keys -X copy-selection-and-cancel \; paste-buffer -p'
  assert_contains "$tmux_config" 'bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-and-cancel'
}

test_tmux_owns_catppuccin_theme_without_plugin() {
  local tmux_config
  tmux_config="$(<"$REPO_DIR/config/unix/.tmux.conf")"

  assert_not_contains "$tmux_config" '@catppuccin_'
  assert_contains "$tmux_config" 'set -g mode-style "bg=#363a4f,bold"'
  assert_contains "$tmux_config" 'set -g status-style "default"'
  assert_contains "$tmux_config" 'set -g menu-selected-style "fg=#cad3f5,bold,bg=#6e738d"'
  assert_contains "$tmux_config" 'set -g popup-style "bg=#24273a,fg=#cad3f5"'
  assert_contains "$tmux_config" 'set -g popup-border-style "fg=#494d64"'
  assert_contains "$tmux_config" 'set -g window-status-current-format'
  assert_contains "$tmux_config" 'set -g status-right '
  assert_contains "$tmux_config" '%Y-%m-%d %H:%M:%S'
}

test_tmux_config_parses_and_applies_theme() {
  local socket="$TEST_TMPDIR/tmux.sock" config="$HOME/.config/tmux/tmux.conf"
  local stderr="$TEST_TMPDIR/tmux.stderr" status=0
  mkdir -p "$(dirname "$config")"
  cp "$REPO_DIR/config/unix/.tmux.conf" "$config"
  _cleanup_tmux_test() {
    trap - RETURN
    env HOME="$HOME" TMUX= tmux -S "$socket" kill-server >/dev/null 2>&1 || true
  }
  trap _cleanup_tmux_test RETURN

  env HOME="$HOME" TMUX= tmux -S "$socket" -f "$config" new-session -d -s audit 'sleep 30' 2> "$stderr" || status=$?

  assert_equals "0" "$status"
  assert_equals "" "$(<"$stderr")"
  if (( status == 0 )); then
    assert_equals "fg=#cad3f5,bold,bg=#6e738d" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv menu-selected-style)"
    assert_equals "bg=#24273a,fg=#cad3f5" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv popup-style)"
    assert_equals "fg=#494d64" "$(env HOME="$HOME" TMUX= tmux -S "$socket" show-options -gv popup-border-style)"
  fi
}
