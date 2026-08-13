#!/usr/bin/env bash

# shellcheck disable=SC1091,SC2016
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

setup() {
  init_test_env
  MOCK_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  cleanup_test_env
}

write_mock() {
  local name="$1"
  shift
  printf '#!/usr/bin/env bash\n%s\n' "$*" > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

test_picker_copies_selected_password_and_clears_it() {
  local script="$REPO_DIR/config/unix/bin/bitwarden-picker"
  assert_file_exists "$script"
  if [[ ! -x "$script" ]]; then
    echo "  bitwarden-picker is not executable" >> "$ERROR_FILE"
    return
  fi

  write_mock rbw '
case "$1 $2" in
  "list --raw") printf '\''[%s]\n'\'' '\''{"name":"Example","folder":"Work","user":"me@example.com","type":"login"}'\'' ;;
  "get --raw") printf '\''%s\n'\'' '\''{"folder":"Work","fields":[{"name":"line\nbreak","value":"custom","type":"hidden"}],"data":{"password":"secret","totp":null,"uris":[{"uri":"https://example.com"}]},"notes":"","name":"Example"}'\'' ;;
  *) exit 2 ;;
esac'
  write_mock fuzzel '
cat > "$TEST_TMPDIR/fuzzel-input-$(( $(cat "$TEST_TMPDIR/fuzzel-count" 2>/dev/null || echo 0) + 1 ))"
count=$(( $(cat "$TEST_TMPDIR/fuzzel-count" 2>/dev/null || echo 0) + 1 ))
printf %s "$count" > "$TEST_TMPDIR/fuzzel-count"
if [[ "$count" == 1 ]]; then printf '\''0\n'\''; else printf '\''%s\n'\'' "${TARGET_INDEX:-1}"; fi'
  write_mock wl-copy '
if [[ "${1:-}" == --clear ]]; then printf CLEAR > "$TEST_TMPDIR/clipboard-cleared"; else cat > "$TEST_TMPDIR/clipboard"; fi'
  write_mock wl-paste 'cat "$TEST_TMPDIR/clipboard"'
  write_mock sleep ':'

  export TEST_TMPDIR
  "$script"

  assert_equals "secret" "$(<"$TEST_TMPDIR/clipboard")"
  assert_equals "CLEAR" "$(<"$TEST_TMPDIR/clipboard-cleared")"
  assert_contains "$(<"$TEST_TMPDIR/fuzzel-input-1")" "Work/Example"
  assert_contains "$(<"$TEST_TMPDIR/fuzzel-input-2")" "Username"
  assert_contains "$(<"$TEST_TMPDIR/fuzzel-input-2")" "Password"
  assert_contains "$(<"$TEST_TMPDIR/fuzzel-input-2")" "Field: line break"
}

test_picker_ignores_invalid_target_index() {
  local script="$REPO_DIR/config/unix/bin/bitwarden-picker"
  write_mock rbw '
case "$1 $2" in
  "list --raw") printf '\''[%s]\n'\'' '\''{"name":"Example","folder":"","user":"me","type":"login"}'\'' ;;
  "get --raw") printf '\''%s\n'\'' '\''{"fields":[],"data":{"password":"secret","totp":null,"uris":[]},"notes":""}'\'' ;;
esac'
  write_mock fuzzel '
cat >/dev/null
count=$(( $(cat "$TEST_TMPDIR/fuzzel-count" 2>/dev/null || echo 0) + 1 ))
printf %s "$count" > "$TEST_TMPDIR/fuzzel-count"
if [[ "$count" == 1 ]]; then printf '\''0\n'\''; else printf '\''99\n'\''; fi'
  write_mock wl-copy 'cat > "$TEST_TMPDIR/clipboard"'
  export TEST_TMPDIR

  "$script"

  [[ ! -e "$TEST_TMPDIR/clipboard" ]] || echo "  invalid target copied clipboard data" >> "$ERROR_FILE"
}
