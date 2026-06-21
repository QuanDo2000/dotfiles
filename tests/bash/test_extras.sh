#!/bin/bash
# Tests for scripts/extras.sh (zsh plugins, tmux plugins).

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

test_install_zsh_plugins_creates_target_dir() {
  mock_cmd git 'mkdir -p "$3/.git"; exit 0'

  (install_zsh_plugins 2>&1) >/dev/null

  local git_dir="$HOME/.local/share/zsh/plugins/zsh-autosuggestions/.git"
  if [ ! -d "$git_dir" ]; then
    echo "  FAILED: install_zsh_plugins should create $git_dir" >> "$ERROR_FILE"
  fi
}

test_install_zsh_plugins_git_clone_failure() {
  # Simulate a flaky network: mock git so `git clone` always exits non-zero.
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
  local plugins_dir="$HOME/.local/share/zsh/plugins"
  mkdir -p "$plugins_dir/zsh-autosuggestions/.git" \
    "$plugins_dir/fast-syntax-highlighting/.git" \
    "$plugins_dir/fzf-tab/.git"
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

test_install_tmux_plugins_already_installed() {
  # tmux-yank + catppuccin already installed (with .git inside, marking
  # complete clones) → no git calls expected. No plugin manager involved.
  mkdir -p "$HOME/.tmux/plugins/tmux-yank/.git" \
    "$HOME/.tmux/plugins/catppuccin/tmux/.git"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_tmux_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_tmux_plugins should not re-clone ($output)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "Finished installing tmux plugins"
}

# ---------------------------------------------------------------------------
# install_codex_plugins
# ---------------------------------------------------------------------------

test_install_codex_plugins_dry_run() {
  DRY=true
  mock_cmd codex 'echo "unexpected codex call: $*" >&2; exit 99'
  local output
  output=$(install_codex_plugins 2>&1)

  assert_contains "$output" "Installing codex plugins"
}

test_install_codex_plugins_runs_install_commands() {
  # Record codex invocations so we can assert all three install steps ran
  # (cache population a fresh machine needs). `login status` and the
  # superpowers `plugin add` both exit 0 to simulate the happy path.
  mock_cmd codex "echo \"\$*\" >> '$HOME/codex-calls.log'"

  local output
  output=$(install_codex_plugins 2>&1)

  local log; log=$(cat "$HOME/codex-calls.log" 2>/dev/null)
  assert_contains "$log" "plugin marketplace add DietrichGebert/ponytail"
  assert_contains "$log" "plugin add ponytail@ponytail"
  assert_contains "$log" "plugin add superpowers@openai-curated"
  assert_contains "$output" "Installed superpowers plugin for codex"
}

# Regression: when `codex login status` exits non-zero OR the openai-curated
# marketplace isn't populated yet (`codex plugin add` fails), skip
# superpowers with a recovery-step message instead of `fail`ing the run.
test_install_codex_plugins_skips_superpowers_when_logged_out() {
  mock_cmd codex "echo \"\$*\" >> '$HOME/codex-calls.log'
if [[ \"\$1\" == \"login\" && \"\$2\" == \"status\" ]]; then exit 1; fi"

  local output
  output=$(install_codex_plugins 2>&1)

  local log; log=$(cat "$HOME/codex-calls.log" 2>/dev/null)
  assert_contains "$log" "plugin add ponytail@ponytail"
  assert_contains "$output" "superpowers plugin skipped"
  assert_contains "$output" "codex login"
  assert_contains "$output" "dotfile extras"
  if [[ "$log" == *"plugin add superpowers"* ]]; then
    echo "  FAILED: superpowers add must not run when login check fails" >> "$ERROR_FILE"
  fi
}

# Regression: even when logged in, the openai-curated marketplace clone
# may not exist yet on a fresh machine. The superpowers `plugin add`
# failure must NOT take down the whole run — just print recovery steps.
test_install_codex_plugins_skips_superpowers_when_marketplace_missing() {
  # login status exits 0 (logged in), but `plugin add superpowers@*` exits 1
  # (the "plugin `superpowers` was not found in marketplace" case).
  mock_cmd codex "echo \"\$*\" >> '$HOME/codex-calls.log'
if [[ \"\$1 \$2\" == \"plugin add\" && \"\$3\" == superpowers@* ]]; then exit 1; fi
exit 0"

  local output exit_code=0
  output=$(install_codex_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: missing-marketplace must skip, not fail (exit=$exit_code)" >> "$ERROR_FILE"
  fi
  assert_contains "$output" "superpowers plugin skipped"
  assert_contains "$output" "codex"
  assert_contains "$output" "dotfile extras"
}

test_install_codex_plugins_propagates_ponytail_failure() {
  # Ponytail failures are still fatal — only the superpowers step is soft.
  # Make `plugin marketplace add` fail; the function must propagate it.
  mock_cmd codex "if [[ \"\$1 \$2\" == \"plugin marketplace\" ]]; then exit 1; fi
exit 0"
  local exit_code=0
  (install_codex_plugins 2>&1) >/dev/null || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo "  FAILED: install_codex_plugins should fail when ponytail add fails" >> "$ERROR_FILE"
  fi
}

# ---------------------------------------------------------------------------
# install_opencode_plugins
# ---------------------------------------------------------------------------

test_install_opencode_plugins_dry_run() {
  DRY=true
  local output
  output=$(install_opencode_plugins 2>&1)

  assert_contains "$output" "Installing opencode plugins"
}

test_install_opencode_plugins_links_commands() {
  # Fake git clone: drop a checkout with a command file so the symlink loop
  # has something to link.
  mock_cmd git 'dest="${@: -1}"; mkdir -p "$dest/.git" "$dest/.opencode/command"; echo "# c" > "$dest/.opencode/command/ponytail.md"'

  (install_opencode_plugins 2>&1) >/dev/null

  assert_symlink "$HOME/.config/opencode/command/ponytail.md" \
    "$HOME/.local/share/ponytail/.opencode/command/ponytail.md"
}

test_install_opencode_plugins_already_installed() {
  local ponytail_dir="$HOME/.local/share/ponytail"
  mkdir -p "$ponytail_dir/.git" "$ponytail_dir/.opencode/command"
  echo "# c" > "$ponytail_dir/.opencode/command/ponytail.md"
  mock_cmd git 'echo "unexpected git call: $*" >&2; exit 99'

  local output exit_code=0
  output=$(install_opencode_plugins 2>&1) || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  FAILED: install_opencode_plugins should not re-clone ($output)" >> "$ERROR_FILE"
  fi
  assert_symlink "$HOME/.config/opencode/command/ponytail.md" \
    "$ponytail_dir/.opencode/command/ponytail.md"
}
