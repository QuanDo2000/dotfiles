#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
NO_DOCKER=false
TEST_FILE=""

for arg in "$@"; do
    case "$arg" in
        --no-docker) NO_DOCKER=true ;;
        *)           TEST_FILE="$arg" ;;
    esac
done

# ---------------------------------------------------------------------------
# Docker orchestration
# ---------------------------------------------------------------------------
in_docker() {
    [ -f /.dockerenv ]
}

run_in_docker() {
    local image_name="dotfiles-test"

    echo "==> Building Docker image..."
    docker build -t "$image_name" -f - . <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils git diffutils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser
DOCKERFILE

    echo "==> Running tests inside Docker container..."
    local docker_args=(
        docker run --rm
        -v "${REPO_DIR}:/home/testuser/dotfiles:ro"
        "$image_name"
        bash /home/testuser/dotfiles/tests/runner.sh --no-docker
    )
    if [ -n "$TEST_FILE" ]; then
        docker_args+=("$TEST_FILE")
    fi
    "${docker_args[@]}"
}

if ! in_docker && [ "$NO_DOCKER" = false ]; then
    run_in_docker
    exit $?
fi

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
    test_funcs="$(declare -F | awk '{print $3}' | grep '^test_')" || true

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

        # Run in subshell with errexit disabled so assertions don't abort early.
        # Assertions communicate failures via ERROR_FILE, not exit codes.
        local exit_code=0
        (
            set +e
            if $has_setup; then setup; fi
            "$t"
            _rc=$?
            if $has_teardown; then teardown; fi
            exit "$_rc"
        ) || exit_code=$?

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

    if [ -n "$TEST_FILE" ]; then
        files=("$SCRIPT_DIR/$TEST_FILE")
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
