#!/usr/bin/env bash
set -euo pipefail

# On Git Bash for Windows, enable native symlinks so `ln -s` produces real
# symlinks instead of file copies. No-op on Linux/macOS where MSYS is unused.
export MSYS=winsymlinks:nativestrict

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_FILES=("$@")
cd "$REPO_DIR"

# ---------------------------------------------------------------------------
# Test framework — assertions
# ---------------------------------------------------------------------------
# ERROR_FILE is created per-test by run_test_file and exported so subshells
# (where test functions run) can append failure messages to it.

assert_equals() {
    local expected="$1" actual="$2"
    if [ "$expected" != "$actual" ]; then
        echo "  assert_equals FAILED: expected '$expected', got '$actual'" >> "$ERROR_FILE"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  assert_contains FAILED: '$haystack' does not contain '$needle'" >> "$ERROR_FILE"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  assert_not_contains FAILED: '$haystack' unexpectedly contains '$needle'" >> "$ERROR_FILE"
    fi
}

assert_file_exists() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "  assert_file_exists FAILED: '$path' does not exist" >> "$ERROR_FILE"
    fi
}

assert_symlink() {
    local path="$1" target="$2"
    if [ ! -L "$path" ]; then
        echo "  assert_symlink FAILED: '$path' is not a symlink" >> "$ERROR_FILE"
        return
    fi
    local actual_target
    actual_target="$(readlink "$path")"
    if [ "$actual_target" != "$target" ]; then
        echo "  assert_symlink FAILED: '$path' -> '$actual_target', expected -> '$target'" >> "$ERROR_FILE"
    fi
}

assert_exit_code() {
    local expected="$1"; shift
    local actual=0
    "$@" || actual=$?
    if [ "$expected" != "$actual" ]; then
        echo "  assert_exit_code FAILED: expected exit code $expected, got $actual for: $*" >> "$ERROR_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Test discovery and execution
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0

run_test_file() {
    local file="$1"
    echo "--- $(basename "$file") ---"

    # Source the test file so its functions are defined in this shell
    source "$file"

    # Discover test_* functions
    local test_funcs
    test_funcs="$(compgen -A function test_)" || true

    if [ -z "$test_funcs" ]; then
        echo "  (no test_* functions found)"
        return
    fi

    # Check for setup/teardown
    local has_setup=false has_teardown=false
    declare -F setup &>/dev/null && has_setup=true
    declare -F teardown &>/dev/null && has_teardown=true

    for t in $test_funcs; do
        TOTAL=$((TOTAL + 1))

        # Fresh error file per test
        ERROR_FILE="$(mktemp)"
        export ERROR_FILE

        # Assertions record failures without returning nonzero. Run test and
        # teardown in nested shells so errexit catches unhandled commands while
        # teardown still runs after a test failure.
        local exit_code=0
        set +e
        (
            local setup_rc=0 setup_last_rc=0 test_rc=0 teardown_rc=0
            if $has_setup; then
                set -E
                trap 'setup_rc=$?' ERR
                setup
                setup_last_rc=$?
                trap - ERR
                (( setup_rc == 0 )) && setup_rc=$setup_last_rc
            fi
            if (( setup_rc == 0 )); then
                (set -e; "$t")
                test_rc=$?
            fi
            if $has_teardown; then
                (set -e; teardown)
                teardown_rc=$?
            fi
            (( setup_rc != 0 )) && exit "$setup_rc"
            (( test_rc != 0 )) && exit "$test_rc"
            exit "$teardown_rc"
        )
        exit_code=$?
        set -e

        # Evaluate results
        local errors=""
        if [ -f "$ERROR_FILE" ]; then
            errors="$(cat "$ERROR_FILE")"
            rm -f "$ERROR_FILE"
        fi

        if [ "$exit_code" -ne 0 ] || [ -n "$errors" ]; then
            FAILED=$((FAILED + 1))
            echo "  FAIL  $t"
            [ "$exit_code" -ne 0 ] && echo "    (exit code: $exit_code)"
            [ -n "$errors" ] && echo "$errors"
        else
            PASSED=$((PASSED + 1))
            echo "  PASS  $t"
        fi
    done

    # Unset test functions and setup/teardown to avoid leaking between files
    for t in $test_funcs; do
        unset -f "$t" 2>/dev/null || true
    done
    unset -f setup teardown 2>/dev/null || true
}

run_tests() {
    local files=()

    if [ ${#TEST_FILES[@]} -gt 0 ]; then
        local test_file
        for test_file in "${TEST_FILES[@]}"; do
            if [[ "$test_file" == /* ]]; then
                files+=("$test_file")
            else
                files+=("$SCRIPT_DIR/$test_file")
            fi
        done
    else
        for f in "$SCRIPT_DIR"/test_*.sh; do
            [ -f "$f" ] && files+=("$f")
        done
    fi

    if [ ${#files[@]} -eq 0 ]; then
        echo "No test files found."
        exit 1
    fi

    for f in "${files[@]}"; do
        run_test_file "$f"
    done

    echo ""
    echo "=== Results: $PASSED passed, $FAILED failed, $TOTAL total ==="

    [ "$FAILED" -gt 0 ] && exit 1
    exit 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
run_tests
