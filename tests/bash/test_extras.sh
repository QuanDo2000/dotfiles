#!/bin/bash
# Tests for scripts/extras.sh (oh-my-zsh, zsh plugins, tmux plugins).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

setup() {
  init_test_env
  source_scripts utils.sh extras.sh
  # Provide a fake bin dir at the front of PATH so we can intercept git/sh/curl.
  FAKE_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
  ORIG_PATH="$PATH"
  export PATH="$FAKE_BIN:$PATH"
}

teardown() {
  export PATH="$ORIG_PATH"
  cleanup_test_env
}

# Helper: install a fake executable in FAKE_BIN that runs $body.
mock_cmd() {
  local name="$1" body="$2"
  cat > "$FAKE_BIN/$name" <<EOF
#!/bin/bash
$body
EOF
  chmod +x "$FAKE_BIN/$name"
}

# ---------------------------------------------------------------------------
# install_oh_my_zsh
# ---------------------------------------------------------------------------

test_install_oh_my_zsh_dry_run() {
  DRY=true
  local output
  output=$(install_oh_my_zsh 2>&1)

  assert_contains "$output" "Installing oh-my-zsh"
  assert_contains "$output" "Finished installing oh-my-zsh"
}

test_install_oh_my_zsh_already_installed() {
  mkdir -p "$HOME/.oh-my-zsh"
  local output
  output=$(install_oh_my_zsh 2>&1)

  assert_contains "$output" "already installed"
}

# ---------------------------------------------------------------------------
# clone_if_missing
# ---------------------------------------------------------------------------

test_clone_if_missing_dry_run_does_not_call_git() {
  DRY=true
  # Canary: any git invocation in DRY mode is a regression.
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(clone_if_missing "test-repo" "https://example.com/repo.git" "$HOME/repo") || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: clone_if_missing should not call git in DRY mode ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Installing test-repo"
  assert_contains "$output" "Would clone https://example.com/repo.git"
  assert_contains "$output" "Finished installing test-repo"
}

test_clone_if_missing_skips_when_dest_exists() {
  # A complete clone is identified by .git/ inside the dest dir.
  mkdir -p "$HOME/repo/.git"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(clone_if_missing "test-repo" "https://example.com/repo.git" "$HOME/repo") || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: clone_if_missing should not call git when dest exists ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing test-repo"
}

test_clone_if_missing_recovers_from_partial_clone() {
  # Pre-existing dest with no .git inside — looks like a partial clone from
  # a prior failed install. Should be wiped and re-cloned.
  mkdir -p "$HOME/repo"
  echo "leftover" > "$HOME/repo/some-file"
  # Mock git clone to succeed, creating the .git marker so the result looks
  # like a real clone.
  mock_cmd git 'mkdir -p "$3/.git"; touch "$3/cloned-marker"; exit 0'

  local output exit_code=0
  output=$(clone_if_missing "test-repo" "https://example.com/repo.git" "$HOME/repo") || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: clone_if_missing should recover from partial clone ($output)" >> "$ERROR_FILE"
  fi
  if [ ! -f "$HOME/repo/cloned-marker" ]; then
    echo "  FAILED: clone_if_missing did not re-clone over the partial dir" >> "$ERROR_FILE"
  fi
  if [ -f "$HOME/repo/some-file" ]; then
    echo "  FAILED: leftover file from partial clone was not removed" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Found partial test-repo install"
}

test_clone_if_missing_does_not_leave_partial_on_failure() {
  # Mock git to fail mid-clone (creates dir, then exits non-zero).
  mock_cmd git 'mkdir -p "$3"; echo "partial" > "$3/file"; exit 1'

  # Wrap in (...) so fail()'s exit 1 stays scoped to the inner subshell.
  (clone_if_missing "test-repo" "https://example.com/repo.git" "$HOME/repo") >/dev/null 2>&1 || true

  if [ -d "$HOME/repo" ]; then
    echo "  FAILED: clone_if_missing left partial dest after git clone failure" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# install_zsh_plugins
# ---------------------------------------------------------------------------

test_install_zsh_plugins_dry_run() {
  DRY=true
  local output
  output=$(install_zsh_plugins 2>&1)

  assert_contains "$output" "Installing zsh plugins"
}

test_install_zsh_plugins_fails_without_oh_my_zsh() {
  # oh-my-zsh dir does not exist → plugin install must fail hard.
  local exit_code=0
  (install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_zsh_plugins should fail when oh-my-zsh is missing" >> "$ERROR_FILE"
  fi
}

test_install_zsh_plugins_git_clone_failure() {
  # Simulate a flaky network: mock git so `git clone` always exits non-zero.
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
  mock_cmd git 'echo "mock git: $*" >&2; exit 42'

  local exit_code=0
  (install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_zsh_plugins should propagate git clone failure" >> "$ERROR_FILE"
  fi
}

test_install_zsh_plugins_all_already_installed() {
  # With every plugin dir present (with .git inside, marking a complete
  # clone), git should never be invoked — mock git as a canary that fails
  # if called so we notice unwanted re-clones.
  local custom="$HOME/.oh-my-zsh/custom"
  mkdir -p "$custom/plugins/zsh-autosuggestions/.git" \
    "$custom/plugins/fast-syntax-highlighting/.git" \
    "$custom/plugins/fzf-tab/.git"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_zsh_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_zsh_plugins should not re-clone existing plugins ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing zsh plugins"
}

# ---------------------------------------------------------------------------
# install_tmux_plugins
# ---------------------------------------------------------------------------

test_install_tmux_plugins_dry_run() {
  DRY=true
  local output
  output=$(install_tmux_plugins 2>&1)

  assert_contains "$output" "Installing tmux plugins"
}

test_install_tmux_plugins_tpm_already_installed() {
  # TPM + catppuccin already installed (with .git inside, marking complete
  # clones) → no git calls expected.
  mkdir -p "$HOME/.tmux/plugins/tpm" "$HOME/.tmux/plugins/catppuccin/tmux/.git"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_tmux_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_tmux_plugins should not re-clone ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Already installed TPM"
}
