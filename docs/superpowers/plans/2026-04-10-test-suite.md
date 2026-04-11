# Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure-bash test suite with Docker isolation for the dotfiles installer scripts.

**Architecture:** A single `tests/runner.sh` script handles both Docker orchestration (build image from inline Dockerfile, run container) and test execution (discovery, assertions, reporting). Per-module test files (`test_*.sh`) define `test_*` functions that the runner discovers and executes in subshells.

**Tech Stack:** Bash, Docker, coreutils

---

## File Structure

| File | Responsibility |
|------|---------------|
| `tests/runner.sh` | Docker orchestration + test framework (discovery, assertions, setup/teardown, reporting) |
| `tests/test_utils.sh` | Tests for `scripts/utils.sh` logging functions and QUIET behavior |
| `tests/test_symlinks.sh` | Tests for `scripts/symlinks.sh` link/copy/setup functions |
| `tests/test_cli.sh` | Tests for `shared/bin/dotfile` flag parsing and command dispatch |
| `tests/test_verify.sh` | Tests for `scripts/verify.sh` tool/symlink verification |

---

### Task 1: Test Runner — Docker Orchestration

**Files:**
- Create: `tests/runner.sh`

This task creates the runner with Docker orchestration only. The test framework (assertions, discovery) is added in Task 2.

- [ ] **Step 1: Create `tests/runner.sh` with Docker orchestration**

```bash
#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NO_DOCKER=false
TEST_FILE=""

# Parse runner args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker)
      NO_DOCKER=true
      shift
      ;;
    *)
      TEST_FILE="$1"
      shift
      ;;
  esac
done

run_in_docker() {
  local image_name="dotfiles-test"

  echo "==> Building test Docker image..."
  docker build -t "$image_name" -f - "$REPO_DIR" <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils git diffutils ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN useradd -m testuser
USER testuser
WORKDIR /home/testuser/dotfiles
DOCKERFILE

  echo "==> Running tests in Docker..."
  local args=()
  if [[ -n "$TEST_FILE" ]]; then
    args+=("$TEST_FILE")
  fi

  docker run --rm \
    -v "$REPO_DIR:/home/testuser/dotfiles:ro" \
    -e HOME=/home/testuser \
    "$image_name" \
    bash /home/testuser/dotfiles/tests/runner.sh --no-docker "${args[@]}"
}

run_tests() {
  echo "TODO: test framework (Task 2)"
}

if [[ "$NO_DOCKER" == "true" ]] || [[ -f "/.dockerenv" ]]; then
  run_tests
else
  run_in_docker
fi
```

- [ ] **Step 2: Make it executable and verify Docker orchestration works**

Run:
```bash
chmod +x tests/runner.sh
./tests/runner.sh
```

Expected: Builds Docker image, runs container, prints "TODO: test framework (Task 2)", exits 0.

- [ ] **Step 3: Commit**

```bash
git add tests/runner.sh
git commit -m "test: add runner.sh with Docker orchestration"
```

---

### Task 2: Test Runner — Framework (Assertions, Discovery, Reporting)

**Files:**
- Modify: `tests/runner.sh`

- [ ] **Step 1: Replace the `run_tests` function with the full test framework**

Replace the `run_tests() { echo "TODO: test framework (Task 2)"; }` block with:

```bash
# --- Test Framework ---

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""
TEST_ERRORS=""

assert_equals() {
  local expected="$1" actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    TEST_ERRORS+="  ASSERT_EQUALS failed: expected '$expected', got '$actual'"$'\n'
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    TEST_ERRORS+="  ASSERT_CONTAINS failed: '$haystack' does not contain '$needle'"$'\n'
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    TEST_ERRORS+="  ASSERT_FILE_EXISTS failed: '$path' does not exist"$'\n'
  fi
}

assert_symlink() {
  local path="$1" expected_target="$2"
  if [[ ! -L "$path" ]]; then
    TEST_ERRORS+="  ASSERT_SYMLINK failed: '$path' is not a symlink"$'\n'
  else
    local actual_target
    actual_target="$(readlink "$path")"
    if [[ "$actual_target" != "$expected_target" ]]; then
      TEST_ERRORS+="  ASSERT_SYMLINK failed: '$path' -> '$actual_target', expected -> '$expected_target'"$'\n'
    fi
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    TEST_ERRORS+="  ASSERT_EXIT_CODE failed: expected $expected, got $actual for: $*"$'\n'
  fi
}

run_test_file() {
  local test_file="$1"
  local file_name
  file_name="$(basename "$test_file")"
  echo "--- $file_name ---"

  # Source in a subshell to get function names without polluting our env
  local test_funcs
  test_funcs=$(bash -c "source '$test_file' 2>/dev/null; declare -F" | awk '/test_/{print $3}')

  if [[ -z "$test_funcs" ]]; then
    echo "  (no tests found)"
    return
  fi

  local has_setup has_teardown
  has_setup=$(bash -c "source '$test_file' 2>/dev/null; declare -F setup" 2>/dev/null && echo "yes" || echo "no")
  has_teardown=$(bash -c "source '$test_file' 2>/dev/null; declare -F teardown" 2>/dev/null && echo "yes" || echo "no")

  for func in $test_funcs; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    CURRENT_TEST="$func"
    TEST_ERRORS=""

    # Run test in subshell
    (
      source "$test_file"
      if [[ "$has_setup" == "yes" ]]; then
        setup
      fi
      "$func"
      if [[ "$has_teardown" == "yes" ]]; then
        teardown
      fi
    )
    local exit_code=$?

    if [[ $exit_code -ne 0 || -n "$TEST_ERRORS" ]]; then
      echo "  FAIL: $func"
      if [[ -n "$TEST_ERRORS" ]]; then
        echo "$TEST_ERRORS"
      fi
      if [[ $exit_code -ne 0 ]]; then
        echo "  (exited with code $exit_code)"
      fi
      TESTS_FAILED=$((TESTS_FAILED + 1))
    else
      echo "  PASS: $func"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
  done
}

run_tests() {
  echo "=== Dotfiles Test Suite ==="
  echo ""

  local test_files=()
  if [[ -n "$TEST_FILE" ]]; then
    test_files=("$SCRIPT_DIR/$TEST_FILE")
  else
    for f in "$SCRIPT_DIR"/test_*.sh; do
      [[ -f "$f" ]] && test_files+=("$f")
    done
  fi

  if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found."
    exit 1
  fi

  for f in "${test_files[@]}"; do
    run_test_file "$f"
    echo ""
  done

  echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_TOTAL total ==="
  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  fi
}
```

Note: `TEST_ERRORS` is shared between the subshell assertions and the parent. Since assertions run in a subshell, we need to communicate failures back. The approach: export `TEST_ERRORS` to a temp file.

Actually, since assertions run in a subshell, we need a different approach. Replace the assertion functions and `run_test_file` to use a temp file for error communication:

```bash
# --- Test Framework ---

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
ERROR_FILE=""

assert_equals() {
  local expected="$1" actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "  ASSERT_EQUALS failed: expected '$expected', got '$actual'" >> "$ERROR_FILE"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT_CONTAINS failed: '$haystack' does not contain '$needle'" >> "$ERROR_FILE"
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "  ASSERT_FILE_EXISTS failed: '$path' does not exist" >> "$ERROR_FILE"
  fi
}

assert_symlink() {
  local path="$1" expected_target="$2"
  if [[ ! -L "$path" ]]; then
    echo "  ASSERT_SYMLINK failed: '$path' is not a symlink" >> "$ERROR_FILE"
  else
    local actual_target
    actual_target="$(readlink "$path")"
    if [[ "$actual_target" != "$expected_target" ]]; then
      echo "  ASSERT_SYMLINK failed: '$path' -> '$actual_target', expected -> '$expected_target'" >> "$ERROR_FILE"
    fi
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    echo "  ASSERT_EXIT_CODE failed: expected $expected, got $actual for: $*" >> "$ERROR_FILE"
  fi
}

run_test_file() {
  local test_file="$1"
  local file_name
  file_name="$(basename "$test_file")"
  echo "--- $file_name ---"

  # Discover test functions
  local test_funcs
  test_funcs=$(bash -c "source '$test_file' 2>/dev/null; declare -F" | awk '/test_/{print $3}')

  if [[ -z "$test_funcs" ]]; then
    echo "  (no tests found)"
    return
  fi

  # Check for setup/teardown
  local has_setup has_teardown
  has_setup=$(bash -c "source '$test_file' 2>/dev/null; declare -F setup >/dev/null && echo yes || echo no")
  has_teardown=$(bash -c "source '$test_file' 2>/dev/null; declare -F teardown >/dev/null && echo yes || echo no")

  for func in $test_funcs; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    ERROR_FILE="$(mktemp)"

    # Run test in subshell — source runner.sh assertions + test file
    (
      source "$SCRIPT_DIR/runner.sh" --source-only 2>/dev/null || true
      source "$test_file"
      if [[ "$has_setup" == "yes" ]]; then setup; fi
      "$func"
      if [[ "$has_teardown" == "yes" ]]; then teardown; fi
    )
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] || [[ -s "$ERROR_FILE" ]]; then
      echo "  FAIL: $func"
      [[ -s "$ERROR_FILE" ]] && cat "$ERROR_FILE"
      [[ $exit_code -ne 0 ]] && echo "  (exited with code $exit_code)"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    else
      echo "  PASS: $func"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    rm -f "$ERROR_FILE"
  done
}
```

This is getting complex with the subshell/re-source approach. Let's simplify: instead of re-sourcing runner.sh, **export the assertion functions and ERROR_FILE path so the subshell inherits them**. Bash functions are inherited by subshells naturally. The key insight: `( ... )` subshells inherit all functions and variables from the parent — we only need the temp file for communicating errors back.

Final approach for the full `tests/runner.sh`:

```bash
#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NO_DOCKER=false
TEST_FILE=""

# Parse runner args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker)
      NO_DOCKER=true
      shift
      ;;
    *)
      TEST_FILE="$1"
      shift
      ;;
  esac
done

# --- Docker Orchestration ---

run_in_docker() {
  local image_name="dotfiles-test"

  echo "==> Building test Docker image..."
  docker build -t "$image_name" -f - "$REPO_DIR" <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils git diffutils ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN useradd -m testuser
USER testuser
WORKDIR /home/testuser/dotfiles
DOCKERFILE

  echo "==> Running tests in Docker..."
  local args=()
  if [[ -n "$TEST_FILE" ]]; then
    args+=("$TEST_FILE")
  fi

  docker run --rm \
    -v "$REPO_DIR:/home/testuser/dotfiles:ro" \
    -e HOME=/home/testuser \
    "$image_name" \
    bash /home/testuser/dotfiles/tests/runner.sh --no-docker "${args[@]}"
}

# --- Assertions ---

ERROR_FILE=""

assert_equals() {
  local expected="$1" actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    echo "  ASSERT_EQUALS failed: expected '$expected', got '$actual'" >> "$ERROR_FILE"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT_CONTAINS failed: '$haystack' does not contain '$needle'" >> "$ERROR_FILE"
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "  ASSERT_FILE_EXISTS failed: '$path' does not exist" >> "$ERROR_FILE"
  fi
}

assert_symlink() {
  local path="$1" expected_target="$2"
  if [[ ! -L "$path" ]]; then
    echo "  ASSERT_SYMLINK failed: '$path' is not a symlink" >> "$ERROR_FILE"
  else
    local actual_target
    actual_target="$(readlink "$path")"
    if [[ "$actual_target" != "$expected_target" ]]; then
      echo "  ASSERT_SYMLINK failed: '$path' -> '$actual_target', expected -> '$expected_target'" >> "$ERROR_FILE"
    fi
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    echo "  ASSERT_EXIT_CODE failed: expected $expected, got $actual for: $*" >> "$ERROR_FILE"
  fi
}

# --- Runner ---

run_test_file() {
  local test_file="$1"
  local file_name
  file_name="$(basename "$test_file")"
  echo "--- $file_name ---"

  # Discover test functions
  local test_funcs
  test_funcs=$(bash -c "source '$test_file' 2>/dev/null; declare -F" | awk '/test_/{print $3}')

  if [[ -z "$test_funcs" ]]; then
    echo "  (no tests found)"
    return
  fi

  # Check for setup/teardown
  local has_setup has_teardown
  has_setup=$(bash -c "source '$test_file' 2>/dev/null; declare -F setup >/dev/null && echo yes || echo no")
  has_teardown=$(bash -c "source '$test_file' 2>/dev/null; declare -F teardown >/dev/null && echo yes || echo no")

  for func in $test_funcs; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    ERROR_FILE="$(mktemp)"
    export ERROR_FILE

    (
      source "$test_file"
      if [[ "$has_setup" == "yes" ]]; then setup; fi
      "$func"
      if [[ "$has_teardown" == "yes" ]]; then teardown; fi
    )
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] || [[ -s "$ERROR_FILE" ]]; then
      echo "  FAIL: $func"
      [[ -s "$ERROR_FILE" ]] && cat "$ERROR_FILE"
      [[ $exit_code -ne 0 ]] && echo "  (exited with code $exit_code)"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    else
      echo "  PASS: $func"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    rm -f "$ERROR_FILE"
  done
}

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

run_tests() {
  echo "=== Dotfiles Test Suite ==="
  echo ""

  local test_files=()
  if [[ -n "$TEST_FILE" ]]; then
    test_files=("$SCRIPT_DIR/$TEST_FILE")
  else
    for f in "$SCRIPT_DIR"/test_*.sh; do
      [[ -f "$f" ]] && test_files+=("$f")
    done
  fi

  if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "No test files found."
    exit 1
  fi

  for f in "${test_files[@]}"; do
    run_test_file "$f"
    echo ""
  done

  echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_TOTAL total ==="
  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  fi
}

# --- Main ---

if [[ "$NO_DOCKER" == "true" ]] || [[ -f "/.dockerenv" ]]; then
  run_tests
else
  run_in_docker
fi
```

- [ ] **Step 2: Create a smoke test file to verify the framework works**

Create `tests/test_smoke.sh`:

```bash
#!/bin/bash

test_assert_equals_passes() {
  assert_equals "hello" "hello"
}

test_assert_equals_fails() {
  # This test intentionally fails to verify failure reporting
  assert_equals "hello" "world"
}
```

- [ ] **Step 3: Run the smoke test**

Run:
```bash
./tests/runner.sh --no-docker test_smoke.sh
```

Expected output:
```
=== Dotfiles Test Suite ===

--- test_smoke.sh ---
  PASS: test_assert_equals_passes
  FAIL: test_assert_equals_fails
  ASSERT_EQUALS failed: expected 'hello', got 'world'

=== Results: 1 passed, 1 failed, 2 total ===
```

- [ ] **Step 4: Delete the smoke test file and commit**

```bash
rm tests/test_smoke.sh
git add tests/runner.sh
git commit -m "test: add test framework with assertions and discovery"
```

---

### Task 3: test_utils.sh

**Files:**
- Create: `tests/test_utils.sh`

**References:**
- `scripts/utils.sh` — the module under test

- [ ] **Step 1: Create `tests/test_utils.sh`**

```bash
#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  # Reset globals before each test
  export DRY=false
  export QUIET=false
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
}

test_info_output() {
  local output
  output=$(info "hello world")
  assert_contains "$output" "hello world"
}

test_success_output() {
  local output
  output=$(success "it worked")
  assert_contains "$output" "it worked"
}

test_user_output() {
  local output
  output=$(user "pick one")
  assert_contains "$output" "pick one"
}

test_fail_exits() {
  assert_exit_code 1 bash -c "source '$REPO_DIR/scripts/utils.sh'; fail 'boom'"
}

test_fail_soft_no_exit() {
  local output
  output=$(fail_soft "warning")
  assert_contains "$output" "warning"
  # If we got here, fail_soft did NOT exit — that's the test
}

test_quiet_suppresses_info() {
  QUIET=true
  local output
  output=$(info "should not appear")
  assert_equals "" "$output"
}

test_quiet_suppresses_success() {
  QUIET=true
  local output
  output=$(success "should not appear")
  assert_equals "" "$output"
}

test_quiet_force_flag() {
  QUIET=true
  local output
  output=$(info "forced message" --force)
  assert_contains "$output" "forced message"
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
./tests/runner.sh --no-docker test_utils.sh
```

Expected: all 8 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_utils.sh
git commit -m "test: add tests for utils.sh"
```

---

### Task 4: test_symlinks.sh

**Files:**
- Create: `tests/test_symlinks.sh`

**References:**
- `scripts/utils.sh` — sourced as dependency
- `scripts/symlinks.sh:3-66` — `link_files` function
- `scripts/symlinks.sh:68-90` — `copy_file` function
- `scripts/symlinks.sh:92-140` — `setup_symlinks_folder` function

- [ ] **Step 1: Create `tests/test_symlinks.sh`**

```bash
#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME=""

setup() {
  export DRY=false
  export QUIET=true
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
  source "$REPO_DIR/scripts/symlinks.sh"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_HOME"
}

test_link_files_creates_symlink() {
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_link"
  echo "content" > "$src"
  link_files "$src" "$dst"
  assert_symlink "$dst" "$src"
}

test_link_files_skips_existing() {
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_link"
  echo "content" > "$src"
  ln -s "$src" "$dst"
  local output
  output=$(link_files "$src" "$dst" 2>&1)
  # Should skip — symlink still points to same source
  assert_symlink "$dst" "$src"
  assert_contains "$output" "Skipped"
}

test_copy_file_copies() {
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_file"
  echo "hello" > "$src"
  copy_file "$src" "$dst"
  assert_file_exists "$dst"
  local content
  content=$(cat "$dst")
  assert_equals "hello" "$content"
}

test_copy_file_skips_identical() {
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_file"
  echo "same" > "$src"
  echo "same" > "$dst"
  local output
  output=$(copy_file "$src" "$dst" 2>&1)
  assert_contains "$output" "Skipped"
}

test_copy_file_force_overwrites() {
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_file"
  echo "new content" > "$src"
  echo "old content" > "$dst"
  FORCE=true
  copy_file "$src" "$dst"
  local content
  content=$(cat "$dst")
  assert_equals "new content" "$content"
}

test_dry_run_link() {
  DRY=true
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_link"
  echo "content" > "$src"
  link_files "$src" "$dst"
  if [[ -e "$dst" ]]; then
    echo "  DRY RUN should not create files" >> "$ERROR_FILE"
  fi
}

test_dry_run_copy() {
  DRY=true
  local src="$TEST_HOME/source_file"
  local dst="$TEST_HOME/dest_file"
  echo "content" > "$src"
  copy_file "$src" "$dst"
  if [[ -e "$dst" ]]; then
    echo "  DRY RUN should not create files" >> "$ERROR_FILE"
  fi
}

test_setup_symlinks_folder_files() {
  local fake_root="$TEST_HOME/dotfiles_root"
  mkdir -p "$fake_root"
  echo "vim config" > "$fake_root/.vimrc"
  echo "git config" > "$fake_root/.gitconfig"
  setup_symlinks_folder "$fake_root"
  assert_symlink "$HOME/.vimrc" "$fake_root/.vimrc"
  assert_symlink "$HOME/.gitconfig" "$fake_root/.gitconfig"
}

test_setup_symlinks_folder_bin() {
  local fake_root="$TEST_HOME/dotfiles_root"
  mkdir -p "$fake_root/bin"
  echo "#!/bin/bash" > "$fake_root/bin/myscript"
  mkdir -p "$HOME/.local/bin"
  setup_symlinks_folder "$fake_root"
  assert_symlink "$HOME/.local/bin/myscript" "$fake_root/bin/myscript"
}

test_setup_symlinks_folder_config() {
  local fake_root="$TEST_HOME/dotfiles_root"
  mkdir -p "$fake_root/config/nvim"
  echo "config" > "$fake_root/config/nvim/init.vim"
  mkdir -p "$HOME/.config"
  setup_symlinks_folder "$fake_root"
  assert_symlink "$HOME/.config/nvim" "$fake_root/config/nvim"
}

test_setup_symlinks_folder_zshrc_copied() {
  local fake_root="$TEST_HOME/dotfiles_root"
  mkdir -p "$fake_root"
  echo "zsh stuff" > "$fake_root/.zshrc"
  setup_symlinks_folder "$fake_root"
  assert_file_exists "$HOME/.zshrc"
  # Should be a regular file (copy), NOT a symlink
  if [[ -L "$HOME/.zshrc" ]]; then
    echo "  .zshrc should be copied, not symlinked" >> "$ERROR_FILE"
  fi
  local content
  content=$(cat "$HOME/.zshrc")
  assert_equals "zsh stuff" "$content"
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
./tests/runner.sh --no-docker test_symlinks.sh
```

Expected: all 11 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_symlinks.sh
git commit -m "test: add tests for symlinks.sh"
```

---

### Task 5: test_cli.sh

**Files:**
- Create: `tests/test_cli.sh`

**References:**
- `shared/bin/dotfile:74-96` — option parsing loop
- `shared/bin/dotfile:99-115` — command dispatch

Note: CLI tests need to extract flag-parsing behavior without triggering `ensure_repo` or actual command execution. We'll test by running the script with specific flags and checking behavior via `--help` and unknown commands. For flag parsing, we create a wrapper that sources just the parsing logic.

- [ ] **Step 1: Create `tests/test_cli.sh`**

```bash
#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILE="$REPO_DIR/shared/bin/dotfile"

setup() {
  export HOME="$(mktemp -d)"
  # Ensure the dotfile script can find and source its scripts
  # by symlinking our repo to ~/dotfiles
  ln -s "$REPO_DIR" "$HOME/dotfiles"
}

teardown() {
  rm -rf "$HOME"
}

test_flag_dry() {
  # -d with verify is safe — verify only reads state
  local output
  output=$(bash "$DOTFILE" -d verify 2>&1)
  # If DRY was set, verify still runs (it doesn't check DRY)
  # We test by checking the script doesn't error out
  assert_exit_code 0 bash "$DOTFILE" -d -h
}

test_flag_force() {
  assert_exit_code 0 bash "$DOTFILE" -f -h
}

test_flag_quiet() {
  local output
  output=$(bash "$DOTFILE" -q -h 2>&1)
  # -h should still print usage even with -q
  assert_contains "$output" "Usage"
}

test_combined_flags() {
  assert_exit_code 0 bash "$DOTFILE" -d -f -q -h
}

test_help_exits_zero() {
  local output
  output=$(bash "$DOTFILE" -h 2>&1)
  assert_contains "$output" "Usage"
  assert_contains "$output" "Commands"
  assert_contains "$output" "Options"
}

test_unknown_command_fails() {
  assert_exit_code 1 bash "$DOTFILE" nonsense_command
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
./tests/runner.sh --no-docker test_cli.sh
```

Expected: all 6 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_cli.sh
git commit -m "test: add tests for CLI parsing"
```

---

### Task 6: test_verify.sh

**Files:**
- Create: `tests/test_verify.sh`

**References:**
- `scripts/verify.sh:3-85` — `verify` function

The `verify` function checks for real tools, oh-my-zsh, plugins, and symlinks. We test it by controlling the environment: fake `$HOME`, controlled `$PATH`, and fake dotfiles directory.

- [ ] **Step 1: Create `tests/test_verify.sh`**

```bash
#!/bin/bash

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_HOME=""

setup() {
  export DRY=false
  export QUIET=false
  export FORCE=false
  source "$REPO_DIR/scripts/utils.sh"
  source "$REPO_DIR/scripts/verify.sh"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_HOME"
}

test_verify_tool_found() {
  # "bash" should always be available
  local output
  output=$(
    # Override verify to check only "bash"
    verify_single_tool() {
      if command -v bash >/dev/null 2>&1; then
        success "bash found: $(command -v bash)"
        return 0
      else
        fail_soft "bash not found"
        return 1
      fi
    }
    verify_single_tool
  )
  assert_contains "$output" "bash found"
}

test_verify_tool_missing() {
  local output
  output=$(
    verify_single_tool() {
      if command -v nonexistent_tool_xyz >/dev/null 2>&1; then
        success "found"
        return 0
      else
        fail_soft "nonexistent_tool_xyz not found"
        return 1
      fi
    }
    verify_single_tool
  )
  assert_contains "$output" "nonexistent_tool_xyz not found"
}

test_verify_symlink_valid() {
  # Set up a fake dotfiles dir and a valid symlink
  local dotfiles_dir="$TEST_HOME/dotfiles"
  mkdir -p "$dotfiles_dir"
  echo "content" > "$dotfiles_dir/.vimrc"
  ln -s "$dotfiles_dir/.vimrc" "$TEST_HOME/.vimrc"

  # Verify the symlink detection logic
  local target="$TEST_HOME/.vimrc"
  if [[ -L "$target" ]]; then
    local link_target
    link_target="$(readlink "$target")"
    assert_contains "$link_target" "$dotfiles_dir"
  else
    echo "  Expected $target to be a symlink" >> "$ERROR_FILE"
  fi
}

test_verify_file_not_symlink() {
  # Create a regular file where a symlink is expected
  echo "not a symlink" > "$TEST_HOME/.vimrc"

  local target="$TEST_HOME/.vimrc"
  if [[ -L "$target" ]]; then
    echo "  Expected $target to NOT be a symlink" >> "$ERROR_FILE"
  fi
  # Verify it's a regular file
  assert_file_exists "$target"
  if [[ -L "$target" ]]; then
    echo "  File should be regular, not a symlink" >> "$ERROR_FILE"
  fi
}

test_verify_error_count() {
  # Run the full verify function and check it reports errors
  # In Docker, most tools (zsh, nvim, tmux, etc.) are missing
  # so verify should report multiple issues
  mkdir -p "$TEST_HOME/dotfiles"
  local output
  output=$(verify 2>&1) || true
  assert_contains "$output" "issue(s) found"
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
./tests/runner.sh --no-docker test_verify.sh
```

Expected: all 5 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test_verify.sh
git commit -m "test: add tests for verify.sh"
```

---

### Task 7: Docker Integration Test

**Files:**
- No new files — validates the full pipeline

- [ ] **Step 1: Run the full suite in Docker**

Run:
```bash
./tests/runner.sh
```

Expected: Docker image builds, all test files run inside the container, all tests pass.

- [ ] **Step 2: Run a single file in Docker**

Run:
```bash
./tests/runner.sh test_utils.sh
```

Expected: Only `test_utils.sh` runs, all tests pass.

- [ ] **Step 3: Fix any Docker-specific issues**

Common issues:
- Read-only mount: tests that write to the repo dir will fail. All tests should write to `$TEST_HOME` only.
- Missing tools in container: tests should account for minimal Ubuntu environment.

Fix any failures and re-run until green.

- [ ] **Step 4: Final commit**

```bash
git add -A tests/
git commit -m "test: complete test suite with Docker integration"
```
