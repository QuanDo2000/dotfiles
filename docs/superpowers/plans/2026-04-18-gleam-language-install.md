# Gleam Language Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Gleam as the third language under `dotfile languages [LANG]`, spanning Linux + macOS + Windows. Auto-installs the Erlang/OTP runtime and rebar3 build helper via each platform's package manager.

**Architecture:** Two parallel implementations — append to `scripts/languages.sh` (mirrors the existing Odin pattern) and to `dotfile.ps1` (introduces a parallel `Install-Languages` umbrella; Windows side has no per-language install today). Layout: versioned per-user dirs (`~/.local/gleam-<tag>/` on Unix, `%LOCALAPPDATA%\Programs\gleam-<tag>\` on Windows) with a stable symlink/junction on PATH. Verification: SHA-256 from each asset's `digest` field in the GitHub releases JSON.

**Tech Stack:** Bash 4+ on Linux/Mac (with bash 3.2 portability for macOS stock bash where required); PowerShell 7+ on Windows. Reuses existing helpers (`_sha256`, `ensure_jq`, `http_get_retry`, `info`/`success`/`fail` on bash; `InvokeRestMethodRetry`, `Info`/`Success`/`Fail`, `AddToUserPath` on PS). No new external runtime dependencies beyond what each platform's package manager provides.

**Spec:** `docs/superpowers/specs/2026-04-18-gleam-language-install-design.md`.

**Pre-execution baseline:**
- Bash (`bash tests/bash/runner.sh --no-docker`): 180 passed / 0 failed on `main` (178/1 inside a worktree; the 1 is the pre-existing path-brittle `test_dotfile_symlinks_command_mac` test).
- PowerShell (`pwsh tests/powershell/runner.ps1`): 48 passed / 1 failed on `main`. The 1 failure is pre-existing: `test_addtouserpath_already_present_does_not_duplicate_process_path` — unrelated to this work, stems from running pwsh on Linux where `[Environment]::GetEnvironmentVariable('Path', 'User')` behaves differently.
- After this plan: ~204 bash, ~57 PowerShell (9 new in test_gleam.ps1 + 2 new in test_args.ps1).

**Cross-platform test runs from this Arch host:** `pwsh` 7.5.4 is available and runs the existing PowerShell test suite fine. `New-Item -ItemType Junction` creates a symlink on Linux (transparent substitute for a Windows junction), so even the `Get-GleamCurrentInstalledVersion` tests that create junctions will work. The only thing that truly can't be exercised here is the full Windows smoke test — that stays deferred to Task 16.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Modify | 7 new functions + extend 2 umbrellas (gleam_target_triple, gleam_latest_release, gleam_current_installed_version, ensure_erlang, ensure_rebar3, install_gleam, update_gleam). |
| `dotfile.ps1` | Modify | 8 new functions + dispatch + usage (Get-GleamTargetTriple, Get-GleamLatestRelease, Get-GleamCurrentInstalledVersion, Install-Erlang, Install-Rebar3, Install-Gleam, Update-Gleam, Install-Languages). Plus a small ParseArgs refactor to expose positional command args. |
| `tests/bash/test_languages.sh` | Modify | ~24 new/changed tests for the bash side. |
| `tests/powershell/test_gleam.ps1` | Create | New file with the PowerShell test suite. |
| `tests/powershell/test_args.ps1` | Modify | One new test for `languages` command parsing. |
| `CLAUDE.md` | Modify | Update existing `dotfile languages [LANG]` line: `(zig, odin)` → `(zig, odin, gleam)`. |

---

## Reused stubbing patterns

**Bash:** Shadow real functions inside the test body and `export -f` so the override propagates into subshells:

```bash
test_xyz() {
  http_get_retry() { cat <<'JSON'
{"tag_name": "v1.15.4", "assets": [...]}
JSON
  }
  export -f http_get_retry
  ...
}
```

For `ensure_*` tests where we need `command -v <bin>` to report "not found" on a host where the binary IS installed, shadow `command` itself:

```bash
command() {
  if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then
    return 1
  fi
  builtin command "$@"
}
export -f command
```

**PowerShell:** Use `Set-CommandMock 'name' { ... }` to shadow native commands; `Clear-CommandMock 'name'` to restore. Use `Set-Item -Path "function:Name"` to shadow PowerShell functions. The runner calls `Reset-DotfileState` between tests, restoring `$script:Dry`/`Quiet`/`Force` to false.

---

## Task 1: `gleam_target_triple`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append to `tests/bash/test_languages.sh`:

```bash
# ---------------------------------------------------------------------------
# gleam_target_triple
# ---------------------------------------------------------------------------

test_gleam_target_triple_linux_x86_64() {
  mock_uname Linux
  mock_uname_m x86_64
  local result
  result="$(gleam_target_triple)"
  assert_equals "x86_64-unknown-linux-musl" "$result"
}

test_gleam_target_triple_linux_aarch64() {
  mock_uname Linux
  mock_uname_m aarch64
  local result
  result="$(gleam_target_triple)"
  assert_equals "aarch64-unknown-linux-musl" "$result"
}

test_gleam_target_triple_macos_x86_64() {
  mock_uname Darwin
  mock_uname_m x86_64
  local result
  result="$(gleam_target_triple)"
  assert_equals "x86_64-apple-darwin" "$result"
}

test_gleam_target_triple_macos_aarch64() {
  mock_uname Darwin
  mock_uname_m arm64
  local result
  result="$(gleam_target_triple)"
  assert_equals "aarch64-apple-darwin" "$result"
}

test_gleam_target_triple_unsupported_arch_fails() {
  mock_uname Linux
  mock_uname_m i686
  local exit_code=0
  ( gleam_target_triple ) >/dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    echo "  FAILED: gleam_target_triple should fail on unsupported arch" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 5 new tests FAIL.

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Map (uname -s, uname -m) to Gleam's release-asset triple (Rust-style).
# Linux uses musl for static linking (no glibc version coupling).
gleam_target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)        echo "x86_64-unknown-linux-musl" ;;
    Linux/aarch64)       echo "aarch64-unknown-linux-musl" ;;
    Linux/arm64)         echo "aarch64-unknown-linux-musl" ;;
    Darwin/x86_64)       echo "x86_64-apple-darwin" ;;
    Darwin/arm64)        echo "aarch64-apple-darwin" ;;
    Darwin/aarch64)      echo "aarch64-apple-darwin" ;;
    *) fail "Unsupported platform for gleam install: $os/$arch" ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: 5 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add gleam_target_triple"
```

---

## Task 2: `gleam_latest_release`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# gleam_latest_release
# ---------------------------------------------------------------------------

test_gleam_latest_release_uses_passed_json() {
  http_get_retry() {
    echo "  FAILED: http_get_retry should not be called when JSON arg supplied" >> "$ERROR_FILE"
    return 1
  }
  export -f http_get_retry

  local result
  result="$(gleam_latest_release '{"tag_name": "v1.15.4"}')"
  assert_equals '{"tag_name": "v1.15.4"}' "$result"
}

test_gleam_latest_release_fetches_when_no_arg() {
  http_get_retry() { echo '{"tag_name": "v1.15.4"}'; }
  export -f http_get_retry

  local result
  result="$(gleam_latest_release)"
  assert_equals '{"tag_name": "v1.15.4"}' "$result"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Print the JSON body of the latest Gleam release from the GitHub API.
# Optionally accepts a JSON string as $1 to skip the network fetch — lets
# install_gleam fetch once and reuse the body for tag/digest/url lookups.
gleam_latest_release() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(http_get_retry "https://api.github.com/repos/gleam-lang/gleam/releases/latest")" \
      || fail "Failed to fetch Gleam releases/latest"
  fi
  echo "$json"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add gleam_latest_release"
```

---

## Task 3: `gleam_current_installed_version`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# gleam_current_installed_version
# ---------------------------------------------------------------------------

test_gleam_current_installed_version_none() {
  local result
  result="$(gleam_current_installed_version)"
  assert_equals "" "$result"
}

test_gleam_current_installed_version_ours_returns_tag() {
  mkdir -p "$HOME/.local/gleam-v1.15.4"
  touch "$HOME/.local/gleam-v1.15.4/gleam"
  ln -s "$HOME/.local/gleam-v1.15.4/gleam" "$HOME/.local/bin/gleam"

  local result
  result="$(gleam_current_installed_version)"
  assert_equals "v1.15.4" "$result"
}

test_gleam_current_installed_version_foreign_returns_empty() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/gleam"
  ln -s "$HOME/elsewhere/gleam" "$HOME/.local/bin/gleam"

  local result
  result="$(gleam_current_installed_version)"
  assert_equals "" "$result"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append to `scripts/languages.sh`:

```bash
# Print the currently-installed Gleam tag IF it was installed by this script.
# Returns empty for: no install, foreign install (system/brew/scoop).
# Detection rule: ~/.local/bin/gleam must be a symlink to ~/.local/gleam-<tag>/gleam.
gleam_current_installed_version() {
  local link="$HOME/.local/bin/gleam"
  [[ -L "$link" ]] || return 0
  local target
  target="$(resolve_symlink "$link")" || return 0
  local prefix="$HOME/.local/gleam-"
  local suffix="/gleam"
  case "$target" in
    "$prefix"*"$suffix")
      local middle="${target#$prefix}"
      middle="${middle%$suffix}"
      case "$middle" in
        */*) return 0 ;;
      esac
      echo "$middle"
      ;;
  esac
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add gleam_current_installed_version"
```

---

## Task 4: `ensure_erlang`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# ensure_erlang
# ---------------------------------------------------------------------------

test_ensure_erlang_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/erl"
  chmod +x "$HOME/.local/bin/erl"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_erlang 2>&1)
  if [[ "$output" == *"Erlang/OTP not found"* ]]; then
    echo "  FAILED: ensure_erlang should noop when erl already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_erlang_dry_run_arch_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}

test_ensure_erlang_dry_run_debian_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}

test_ensure_erlang_dry_run_mac_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "erl" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output
  output=$(ensure_erlang 2>&1)
  assert_contains "$output" "Erlang/OTP not found"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append:

```bash
# Install Erlang/OTP via the platform package manager if missing. Required
# for Gleam runtime (gleam compiles to BEAM bytecode).
ensure_erlang() {
  if command -v erl >/dev/null 2>&1; then
    return 0
  fi
  info "Erlang/OTP not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y erlang || fail "Failed to install erlang" ;;
    arch)   sudo pacman -S --needed --noconfirm erlang || fail "Failed to install erlang" ;;
    mac)    brew install erlang || fail "Failed to install erlang" ;;
    *)      fail "Cannot install Erlang on this platform" ;;
  esac
  success "Installed Erlang/OTP"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add ensure_erlang helper"
```

---

## Task 5: `ensure_rebar3`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

Identical shape to `ensure_erlang`, just substitute `rebar3` for `erlang` and `Erlang/OTP` for `rebar3`.

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# ensure_rebar3
# ---------------------------------------------------------------------------

test_ensure_rebar3_already_present_noop() {
  echo '#!/bin/bash' > "$HOME/.local/bin/rebar3"
  chmod +x "$HOME/.local/bin/rebar3"
  export PATH="$HOME/.local/bin:$PATH"

  local output
  output=$(ensure_rebar3 2>&1)
  if [[ "$output" == *"rebar3 not found"* ]]; then
    echo "  FAILED: ensure_rebar3 should noop when already on PATH" >> "$ERROR_FILE"
  fi
}

test_ensure_rebar3_dry_run_arch_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "arch"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}

test_ensure_rebar3_dry_run_debian_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "debian"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}

test_ensure_rebar3_dry_run_mac_logs_install() {
  DRY=true
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "rebar3" ]]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  detect_platform() { echo "mac"; }
  export -f detect_platform

  local output
  output=$(ensure_rebar3 2>&1)
  assert_contains "$output" "rebar3 not found"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append:

```bash
# Install rebar3 via the platform package manager if missing. Optional Gleam
# build helper — only some projects need it, but cheap to install upfront.
ensure_rebar3() {
  if command -v rebar3 >/dev/null 2>&1; then
    return 0
  fi
  info "rebar3 not found; installing..."
  if [[ "$DRY" == "true" ]]; then
    return 0
  fi
  case "$(detect_platform)" in
    debian) sudo apt install -y rebar3 || fail "Failed to install rebar3" ;;
    arch)   sudo pacman -S --needed --noconfirm rebar3 || fail "Failed to install rebar3" ;;
    mac)    brew install rebar3 || fail "Failed to install rebar3" ;;
    *)      fail "Cannot install rebar3 on this platform" ;;
  esac
  success "Installed rebar3"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add ensure_rebar3 helper"
```

---

## Task 6: `install_gleam`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

The full implementation. Only dry-run + already-installed paths are unit-testable; download/SHA/extract validated by manual smoke test (Task 16). **Differs from `install_odin`:** Gleam tarballs extract flat (just the binary), not a top-level directory — replace the find-loop guard with a single-file check.

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# install_gleam
# ---------------------------------------------------------------------------

test_install_gleam_dry_run() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
  assert_contains "$output" "Finished"
  if [[ -e "$HOME/.local/gleam-v1.15.4" ]]; then
    echo "  FAILED: dry run created install dir" >> "$ERROR_FILE"
  fi
}

test_install_gleam_already_installed_short_circuits() {
  mkdir -p "$HOME/.local/gleam-v1.15.4"
  touch "$HOME/.local/gleam-v1.15.4/gleam"
  ln -s "$HOME/.local/gleam-v1.15.4/gleam" "$HOME/.local/bin/gleam"

  http_get_retry() { echo '{"tag_name": "v1.15.4", "assets": []}'; }
  export -f http_get_retry
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_gleam 2>&1)
  assert_contains "$output" "Already installed Gleam v1.15.4"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append:

```bash
# Install (or upgrade) Gleam from the official GitHub releases.
# Layout: extracts to ~/.local/gleam-<tag>/gleam and symlinks ~/.local/bin/gleam.
# Auto-installs Erlang/OTP and rebar3 dependencies. Skips if at the target tag.
install_gleam() {
  info "Installing Gleam..."
  ensure_jq
  ensure_erlang
  ensure_rebar3

  local triple
  triple="$(gleam_target_triple)"
  if [[ "$DRY" == "true" ]]; then
    info "Would install latest Gleam for $triple"
    success "Finished installing Gleam (dry run)"
    return 0
  fi

  local release_json
  release_json="$(gleam_latest_release)"

  local tag
  tag="$(echo "$release_json" | jq -r '.tag_name // empty')"
  if [[ -z "$tag" ]]; then
    fail "Could not read tag_name from Gleam releases/latest"
  fi
  local asset="gleam-${tag}-${triple}.tar.gz"

  local current
  current="$(gleam_current_installed_version)"
  if [[ "$current" == "$tag" ]]; then
    success "Already installed Gleam $tag"
    return 0
  fi

  local digest
  digest="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .digest // empty')"
  if [[ -z "$digest" ]]; then
    fail "Could not find digest for $asset in Gleam releases/latest"
  fi
  # GitHub formats digests as "sha256:<hex>"; strip the prefix.
  # If the prefix is absent (e.g. "sha512:" or bare hex), the expansion is a
  # no-op, so expected_sha == digest — fail loudly rather than compare against
  # a value of unknown algorithm.
  local expected_sha="${digest#sha256:}"
  if [[ "$expected_sha" == "$digest" ]]; then
    fail "Unexpected digest format for $asset: $digest"
  fi

  local asset_url
  asset_url="$(echo "$release_json" | jq -r --arg a "$asset" \
    '.assets[] | select(.name == $a) | .browser_download_url // empty')"
  if [[ -z "$asset_url" ]]; then
    fail "Could not find download URL for $asset in Gleam releases/latest"
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  local tar_path="$tmpdir/$asset"
  info "Downloading $asset_url"
  curl -sfL "$asset_url" -o "$tar_path" \
    || fail "Failed to download $asset_url"

  local got_sha
  got_sha="$(_sha256 "$tar_path")"
  if [[ "$got_sha" != "$expected_sha" ]]; then
    fail "sha256 mismatch for $asset (expected $expected_sha, got $got_sha)"
  fi

  # Gleam tarballs extract flat — just the `gleam` binary at the archive root,
  # NO top-level directory. This differs from Zig and Odin tarballs.
  local extract_dir="$tmpdir/extract"
  mkdir -p "$extract_dir"
  tar -xf "$tar_path" -C "$extract_dir" \
    || fail "Failed to extract Gleam tarball"
  if [[ ! -f "$extract_dir/gleam" ]]; then
    fail "Gleam binary not found at top level of tarball"
  fi

  local target_dir="$HOME/.local/gleam-$tag"
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  mv "$extract_dir/gleam" "$target_dir/gleam" \
    || fail "Failed to move Gleam binary into place"

  mkdir -p "$HOME/.local/bin"
  ln -sfn "$target_dir/gleam" "$HOME/.local/bin/gleam" \
    || fail "Failed to create ~/.local/bin/gleam symlink"

  # Clean up old versions (any ~/.local/gleam-*/ that isn't the current one).
  # The [[ -d ]] guard handles the no-matches case where the glob returns
  # the literal pattern unchanged.
  local old
  for old in "$HOME"/.local/gleam-*; do
    [[ -d "$old" && "$old" != "$target_dir" ]] && rm -rf "$old"
  done

  success "Installed Gleam $tag"
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add install_gleam with SHA-256 verification"
```

---

## Task 7: `update_gleam`

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Write failing tests**

Append:

```bash
# ---------------------------------------------------------------------------
# update_gleam
# ---------------------------------------------------------------------------

test_update_gleam_no_op_when_not_installed() {
  local output
  output=$(update_gleam 2>&1)
  assert_equals "" "$output"
}

test_update_gleam_skips_foreign_install() {
  mkdir -p "$HOME/elsewhere"
  touch "$HOME/elsewhere/gleam"
  ln -s "$HOME/elsewhere/gleam" "$HOME/.local/bin/gleam"

  local output
  output=$(update_gleam 2>&1)
  assert_equals "" "$output"
}

test_update_gleam_dry_run_when_ours() {
  DRY=true
  mkdir -p "$HOME/.local/gleam-v1.14.0"
  touch "$HOME/.local/gleam-v1.14.0/gleam"
  ln -s "$HOME/.local/gleam-v1.14.0/gleam" "$HOME/.local/bin/gleam"

  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(update_gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 3: Implement**

Append:

```bash
# Update Gleam — but only if it was installed by this script. Foreign installs
# (system, brew, scoop) are left alone.
update_gleam() {
  local current
  current="$(gleam_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_gleam
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add update_gleam"
```

---

## Task 8: Extend bash umbrellas

**Files:**
- Modify: `scripts/languages.sh`
- Modify: `tests/bash/test_languages.sh`

- [ ] **Step 1: Update existing tests + add a new one**

In `tests/bash/test_languages.sh`, REPLACE the body of `test_install_languages_all_arg`:

```bash
test_install_languages_all_arg() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages all 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
}
```

REPLACE `test_install_languages_dry_run`:

```bash
test_install_languages_dry_run() {
  DRY=true
  ensure_minisign() { return 0; }
  export -f ensure_minisign
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages 2>&1)
  assert_contains "$output" "Installing Zig"
  assert_contains "$output" "Installing Odin"
  assert_contains "$output" "Installing Gleam"
}
```

APPEND a new test:

```bash
test_install_languages_gleam_only_arg() {
  DRY=true
  ensure_jq() { return 0; }
  export -f ensure_jq
  ensure_erlang() { return 0; }
  export -f ensure_erlang
  ensure_rebar3() { return 0; }
  export -f ensure_rebar3

  local output
  output=$(install_languages gleam 2>&1)
  assert_contains "$output" "Installing Gleam"
  if [[ "$output" == *"Installing Zig"* ]]; then
    echo "  FAILED: install_languages gleam should not run Zig" >> "$ERROR_FILE"
  fi
  if [[ "$output" == *"Installing Odin"* ]]; then
    echo "  FAILED: install_languages gleam should not run Odin" >> "$ERROR_FILE"
  fi
}
```

- [ ] **Step 2: Run, confirm failure**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```
Expected: `_gleam_only_arg` FAILs (no `gleam)` arm yet); the updated `_all_arg` and `_dry_run` tests also FAIL.

- [ ] **Step 3: Implement**

Edit `install_languages` in `scripts/languages.sh`. Replace its body with:

```bash
install_languages() {
  local target="${1:-all}"
  case "$target" in
    all|"") install_zig; install_odin; install_gleam ;;
    zig)    install_zig ;;
    odin)   install_odin ;;
    gleam)  install_gleam ;;
    *)      fail "Unknown language: $target" ;;
  esac
}
```

Replace `update_languages`:

```bash
update_languages() {
  update_zig
  update_odin
  update_gleam
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
bash tests/bash/runner.sh --no-docker test_languages.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/languages.sh tests/bash/test_languages.sh
git commit -m "Add Gleam to install_languages and update_languages umbrellas"
```

---

## Task 9: PowerShell `Get-GleamTargetTriple` + `Get-GleamLatestRelease` + `Get-GleamCurrentInstalledVersion`

**Files:**
- Modify: `dotfile.ps1`
- Create: `tests/powershell/test_gleam.ps1`

Three small Get-* helpers in one task — all are pure parsing functions.

**IMPORTANT:** This Arch dev host has no `pwsh`. You CANNOT run `pwsh tests/powershell/runner.ps1` here. Write the PowerShell tests following the patterns in `tests/powershell/test_args.ps1` and `tests/powershell/test_dry_installers.ps1`. Verify the test file syntactically by reviewing — the actual run happens on a Windows machine later.

- [ ] **Step 1: Create the test file with failing tests**

Create `tests/powershell/test_gleam.ps1`:

```powershell
# Tests for Gleam install helpers in dotfile.ps1.

function TestSetup {
    Initialize-TestEnv | Out-Null
}

function TestTeardown {
    Clear-TestEnv
}

# ---------------------------------------------------------------------------
# Get-GleamTargetTriple
# ---------------------------------------------------------------------------

function test_get_gleam_target_triple_returns_msvc_on_x64 {
    # On the test runner (always 64-bit), this should resolve.
    $result = Get-GleamTargetTriple
    Assert-Equals 'x86_64-pc-windows-msvc' $result
}

# ---------------------------------------------------------------------------
# Get-GleamLatestRelease
# ---------------------------------------------------------------------------

function test_get_gleam_latest_release_uses_passed_json {
    # If a JSON arg is passed, the function returns it verbatim and never
    # calls InvokeRestMethodRetry. We verify by replacing the helper with
    # one that fails the test if invoked.
    Set-Item -Path 'function:script:InvokeRestMethodRetry' -Value {
        param($Uri, $Headers, $MaxAttempts)
        $script:Errors.Add('  FAILED: InvokeRestMethodRetry should not be called when JSON arg supplied')
        throw 'should not be reached'
    }
    try {
        $result = Get-GleamLatestRelease -Json '{"tag_name": "v1.15.4"}'
        Assert-Equals '{"tag_name": "v1.15.4"}' $result
    } finally {
        Remove-Item 'function:script:InvokeRestMethodRetry' -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Get-GleamCurrentInstalledVersion
# ---------------------------------------------------------------------------

function test_get_gleam_current_installed_version_none {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals '' $result
}

function test_get_gleam_current_installed_version_ours_returns_tag {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $versioned = Join-Path $programs 'gleam-v1.15.4'
    New-Item -ItemType Directory -Force -Path $versioned | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $programs 'gleam') -Target $versioned | Out-Null

    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals 'v1.15.4' $result
}

function test_get_gleam_current_installed_version_foreign_returns_empty {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $foreign = Join-Path $script:_TestTmp.FullName 'elsewhere'
    New-Item -ItemType Directory -Force -Path $foreign | Out-Null
    New-Item -ItemType Directory -Force -Path $programs | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $programs 'gleam') -Target $foreign | Out-Null

    $result = Get-GleamCurrentInstalledVersion
    Assert-Equals '' $result
}
```

- [ ] **Step 2: Implement the three helpers in `dotfile.ps1`**

Add these functions to `dotfile.ps1` (place them grouped together — adjacent to `InstallNeovimNightly` is a reasonable location since both manage `%LOCALAPPDATA%\Programs\` installs):

```powershell
function Get-GleamTargetTriple {
    if (-not [System.Environment]::Is64BitOperatingSystem) {
        Fail "Unsupported architecture for Gleam (need 64-bit Windows)"
    }
    return 'x86_64-pc-windows-msvc'
}

function Get-GleamLatestRelease {
    param([string]$Json = $null)
    if (-not $Json) {
        $obj = InvokeRestMethodRetry -Uri 'https://api.github.com/repos/gleam-lang/gleam/releases/latest'
        $Json = ConvertTo-Json -InputObject $obj -Depth 100 -Compress
    }
    return $Json
}

function Get-GleamCurrentInstalledVersion {
    $junction = Join-Path $env:LOCALAPPDATA 'Programs\gleam'
    if (-not (Test-Path -LiteralPath $junction)) { return '' }
    $item = Get-Item -LiteralPath $junction -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.Target) { return '' }
    $target = if ($item.Target -is [array]) { $item.Target[0] } else { $item.Target }
    $prefix = Join-Path $env:LOCALAPPDATA 'Programs\gleam-'
    if ($target.StartsWith($prefix)) {
        return $target.Substring($prefix.Length)
    }
    return ''
}
```

- [ ] **Step 3: Manual syntax check (no `pwsh` available here)**

Read the new code and confirm:
- Each function has correct PowerShell syntax (no missing braces, semicolons where needed, etc.).
- `Get-GleamCurrentInstalledVersion` uses `-LiteralPath` consistently.
- The junction `.Target` may be an array on PS7, so the `if ($item.Target -is [array])` guard is correct.

- [ ] **Step 4: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Add Gleam Get-* helpers in dotfile.ps1"
```

---

## Task 10: PowerShell `Install-Erlang` + `Install-Rebar3`

**Files:**
- Modify: `dotfile.ps1`
- Modify: `tests/powershell/test_gleam.ps1`

- [ ] **Step 1: Append failing tests**

Append to `tests/powershell/test_gleam.ps1`:

```powershell
# ---------------------------------------------------------------------------
# Install-Erlang
# ---------------------------------------------------------------------------

function test_install_erlang_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }
    Set-CommandMock 'erl' { throw 'should not be invoked' }  # so Get-Command returns null
    Remove-Item function:erl  # actually we just want erl absent; mock doesn't help here

    # Simpler approach: shadow Get-Command for 'erl' specifically
    Set-Item -Path 'function:script:Get-Command' -Value {
        param($Name)
        if ($Name -eq 'erl') { return $null }
        Microsoft.PowerShell.Core\Get-Command @args
    }
    try {
        $output = Install-Erlang 6>&1 | Out-String
    } finally {
        Remove-Item 'function:script:Get-Command' -ErrorAction SilentlyContinue
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'Erlang/OTP not found'
    Assert-False $script:called 'scoop should not be invoked in dry run'
}

# ---------------------------------------------------------------------------
# Install-Rebar3
# ---------------------------------------------------------------------------

function test_install_rebar3_dry_run_does_not_call_scoop {
    $script:Dry = $true
    $called = $false
    Set-CommandMock 'scoop' { $script:called = $true }
    Set-Item -Path 'function:script:Get-Command' -Value {
        param($Name)
        if ($Name -eq 'rebar3') { return $null }
        Microsoft.PowerShell.Core\Get-Command @args
    }
    try {
        $output = Install-Rebar3 6>&1 | Out-String
    } finally {
        Remove-Item 'function:script:Get-Command' -ErrorAction SilentlyContinue
        Clear-CommandMock 'scoop'
    }

    Assert-Contains $output 'rebar3 not found'
    Assert-False $script:called 'scoop should not be invoked in dry run'
}
```

- [ ] **Step 2: Implement in `dotfile.ps1`**

Add adjacent to the new Get-* helpers:

```powershell
function Install-Erlang {
    if (Get-Command -Name 'erl' -ErrorAction SilentlyContinue) { return }
    Info 'Erlang/OTP not found; installing...'
    if ($script:Dry) { return }
    scoop bucket add main *> $null
    scoop install main/erlang
    if ($LASTEXITCODE -ne 0) { Fail 'Failed to install erlang via scoop' }
    Success 'Installed Erlang/OTP'
}

function Install-Rebar3 {
    if (Get-Command -Name 'rebar3' -ErrorAction SilentlyContinue) { return }
    Info 'rebar3 not found; installing...'
    if ($script:Dry) { return }
    scoop bucket add main *> $null
    scoop install main/rebar3
    if ($LASTEXITCODE -ne 0) { Fail 'Failed to install rebar3 via scoop' }
    Success 'Installed rebar3'
}
```

- [ ] **Step 3: Manual syntax check**

Confirm:
- Both functions use `Get-Command ... -ErrorAction SilentlyContinue` to detect missing binary (matches existing pattern in `dotfile.ps1`).
- Both respect `$script:Dry`.
- `*> $null` redirects all streams (stdout, stderr, etc.) — used to silence scoop's bucket-already-exists chatter.

- [ ] **Step 4: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Add Install-Erlang and Install-Rebar3 in dotfile.ps1"
```

---

## Task 11: PowerShell `Install-Gleam`

**Files:**
- Modify: `dotfile.ps1`
- Modify: `tests/powershell/test_gleam.ps1`

The big one. Mirrors the bash `install_gleam` flow with Windows idioms (Invoke-WebRequest, Get-FileHash, Expand-Archive, junction).

- [ ] **Step 1: Append failing tests**

Append to `tests/powershell/test_gleam.ps1`:

```powershell
# ---------------------------------------------------------------------------
# Install-Gleam
# ---------------------------------------------------------------------------

function test_install_gleam_dry_run {
    $script:Dry = $true
    $env:LOCALAPPDATA = $script:_TestTmp.FullName

    # Stub the dependency installs so the dry-run test doesn't need scoop/erl.
    Set-Item -Path 'function:script:Install-Erlang' -Value { }
    Set-Item -Path 'function:script:Install-Rebar3' -Value { }

    $output = Install-Gleam 6>&1 | Out-String

    Remove-Item 'function:script:Install-Erlang' -ErrorAction SilentlyContinue
    Remove-Item 'function:script:Install-Rebar3' -ErrorAction SilentlyContinue

    Assert-Contains $output 'Installing Gleam'
    Assert-Contains $output 'Finished'
    $created = Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\gleam-v1.15.4')
    Assert-False $created 'dry run should not create install dir'
}

function test_install_gleam_already_installed_short_circuits {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $versioned = Join-Path $programs 'gleam-v1.15.4'
    New-Item -ItemType Directory -Force -Path $versioned | Out-Null
    New-Item -ItemType File -Force -Path (Join-Path $versioned 'gleam.exe') | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $programs 'gleam') -Target $versioned | Out-Null

    Set-Item -Path 'function:script:Install-Erlang' -Value { }
    Set-Item -Path 'function:script:Install-Rebar3' -Value { }
    Set-Item -Path 'function:script:InvokeRestMethodRetry' -Value {
        param($Uri, $Headers, $MaxAttempts)
        return @{ tag_name = 'v1.15.4'; assets = @() }
    }

    try {
        $output = Install-Gleam 6>&1 | Out-String
    } finally {
        Remove-Item 'function:script:Install-Erlang' -ErrorAction SilentlyContinue
        Remove-Item 'function:script:Install-Rebar3' -ErrorAction SilentlyContinue
        Remove-Item 'function:script:InvokeRestMethodRetry' -ErrorAction SilentlyContinue
    }

    Assert-Contains $output 'Already installed Gleam v1.15.4'
}
```

- [ ] **Step 2: Implement in `dotfile.ps1`**

Add adjacent to the other Gleam functions:

```powershell
function Install-Gleam {
    Info 'Installing Gleam...'
    Install-Erlang
    Install-Rebar3

    $triple = Get-GleamTargetTriple
    if ($script:Dry) {
        Info "Would install latest Gleam for $triple"
        Success 'Finished installing Gleam (dry run)'
        return
    }

    $releaseJson = Get-GleamLatestRelease
    $release = $releaseJson | ConvertFrom-Json

    $tag = $release.tag_name
    if (-not $tag) { Fail 'Could not read tag_name from Gleam releases/latest' }
    $asset = "gleam-$tag-$triple.zip"

    $current = Get-GleamCurrentInstalledVersion
    if ($current -eq $tag) {
        Success "Already installed Gleam $tag"
        return
    }

    $assetMeta = $release.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1
    if (-not $assetMeta) { Fail "Could not find asset $asset in Gleam releases/latest" }

    $digest = $assetMeta.digest
    if (-not $digest) { Fail "Could not find digest for $asset" }
    if (-not $digest.StartsWith('sha256:')) {
        Fail "Unexpected digest format for ${asset}: $digest"
    }
    $expectedSha = $digest.Substring('sha256:'.Length)

    $url = $assetMeta.browser_download_url
    if (-not $url) { Fail "Could not find download URL for $asset" }

    $tmpZip = New-TemporaryFile
    Rename-Item $tmpZip "$($tmpZip.FullName).zip"
    $tmpZip = Get-Item "$($tmpZip.FullName).zip"
    $tmpExtract = Join-Path ([System.IO.Path]::GetTempPath()) ("gleam-extract-$([Guid]::NewGuid().ToString('N'))")

    try {
        Info "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $tmpZip.FullName -UseBasicParsing

        $gotSha = (Get-FileHash -Path $tmpZip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($gotSha -ne $expectedSha.ToLowerInvariant()) {
            Fail "sha256 mismatch for $asset (expected $expectedSha, got $gotSha)"
        }

        New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null
        Expand-Archive -Path $tmpZip.FullName -DestinationPath $tmpExtract -Force
        $extractedExe = Join-Path $tmpExtract 'gleam.exe'
        if (-not (Test-Path -LiteralPath $extractedExe)) {
            Fail 'gleam.exe not found at top level of zip'
        }

        $programs = Join-Path $env:LOCALAPPDATA 'Programs'
        $targetDir = Join-Path $programs "gleam-$tag"
        if (Test-Path -LiteralPath $targetDir) { Remove-Item -Recurse -Force $targetDir }
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        Move-Item $extractedExe (Join-Path $targetDir 'gleam.exe')

        $junction = Join-Path $programs 'gleam'
        if (Test-Path -LiteralPath $junction) { Remove-Item -Force $junction }
        New-Item -ItemType Junction -Path $junction -Target $targetDir | Out-Null

        AddToUserPath $junction

        # Clean up old versioned dirs
        Get-ChildItem -Path $programs -Directory -Filter 'gleam-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $targetDir } |
            ForEach-Object { Remove-Item -Recurse -Force $_.FullName }

        Success "Installed Gleam $tag"
    } finally {
        if (Test-Path -LiteralPath $tmpZip.FullName) { Remove-Item -Force $tmpZip.FullName }
        if (Test-Path -LiteralPath $tmpExtract) { Remove-Item -Recurse -Force $tmpExtract }
    }
}
```

- [ ] **Step 3: Manual syntax check**

Confirm:
- The `try/finally` cleans up both the zip and extract dir even on `Fail` paths (note: `Fail` calls `exit 1`, which still triggers `finally` blocks in PowerShell).
- Junction creation uses `New-Item -ItemType Junction` (works on Windows even without admin).
- `AddToUserPath` is the existing helper in `dotfile.ps1`.
- Get-FileHash output is uppercase hex by default; comparison uses `.ToLowerInvariant()` to match GitHub's lowercase digest.
- Cleanup loop uses `Get-ChildItem -Filter 'gleam-*'` so it only matches our prefix.

- [ ] **Step 4: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1
git commit -m "Add Install-Gleam in dotfile.ps1"
```

---

## Task 12: PowerShell `Update-Gleam` + `Install-Languages` + CLI wiring

**Files:**
- Modify: `dotfile.ps1`
- Modify: `tests/powershell/test_gleam.ps1`
- Modify: `tests/powershell/test_args.ps1`

Adds the umbrella + the CLI dispatch + the `ParseArgs` change to expose the second positional arg.

- [ ] **Step 1: Append PowerShell tests**

Append to `tests/powershell/test_gleam.ps1`:

```powershell
# ---------------------------------------------------------------------------
# Update-Gleam
# ---------------------------------------------------------------------------

function test_update_gleam_no_op_when_not_installed {
    $env:LOCALAPPDATA = $script:_TestTmp.FullName
    $output = Update-Gleam 6>&1 | Out-String
    Assert-Equals '' $output.Trim()
}

# ---------------------------------------------------------------------------
# Install-Languages
# ---------------------------------------------------------------------------

function test_install_languages_dispatches_gleam_only {
    $script:Dry = $true
    Set-Item -Path 'function:script:Install-Gleam' -Value { Info 'STUB Install-Gleam called' }

    $output = Install-Languages -Target 'gleam' 6>&1 | Out-String

    Remove-Item 'function:script:Install-Gleam' -ErrorAction SilentlyContinue
    Assert-Contains $output 'STUB Install-Gleam called'
}

function test_install_languages_unknown_fails {
    $threw = $false
    try {
        Install-Languages -Target 'java'
    } catch {
        $threw = $true
    }
    Assert-True $threw 'Install-Languages java should throw'
}
```

Append to `tests/powershell/test_args.ps1`:

```powershell
function test_parseargs_languages_command_recognised {
    $cmd = ParseArgs @('languages')
    Assert-Equals 'languages' $cmd
}

function test_parseargs_languages_with_lang_arg_exposes_second_positional {
    $cmd = ParseArgs @('languages', 'gleam')
    Assert-Equals 'languages' $cmd
    Assert-Equals 'gleam' $script:CommandArg
}
```

- [ ] **Step 2: Implement Update-Gleam + Install-Languages in `dotfile.ps1`**

Append to the Gleam functions block:

```powershell
function Update-Gleam {
    if (-not (Get-GleamCurrentInstalledVersion)) { return }
    Install-Gleam
}

function Install-Languages {
    param([string]$Target = 'all')
    switch ($Target) {
        { $_ -in @('all', '', 'gleam') } { Install-Gleam }
        default { Fail "Unknown language: $Target" }
    }
}
```

- [ ] **Step 3: Refactor `ParseArgs` to expose the second positional**

Find `ParseArgs` in `dotfile.ps1` (around line 556). The current implementation collects positionals but only returns the first one. Add `$script:CommandArg` so the dispatch can read it:

Replace the function body. Current:

```powershell
function ParseArgs([string[]]$Arguments) {
    $command = "all"
    $positional = @()
    foreach ($arg in $Arguments) {
        switch ($arg) {
            { $_ -in "-d", "--dry" }   { $script:Dry = $true }
            { $_ -in "-f", "--force" } { $script:Force = $true }
            { $_ -in "-q", "--quiet" } { $script:Quiet = $true }
            { $_ -in "-h", "--help" }  { ShowUsage; return '__help__' }
            default { $positional += $arg }
        }
    }
    if ($positional.Count -gt 0) { $command = $positional[0] }
    return $command
}
```

Replace with:

```powershell
function ParseArgs([string[]]$Arguments) {
    $command = "all"
    $positional = @()
    foreach ($arg in $Arguments) {
        switch ($arg) {
            { $_ -in "-d", "--dry" }   { $script:Dry = $true }
            { $_ -in "-f", "--force" } { $script:Force = $true }
            { $_ -in "-q", "--quiet" } { $script:Quiet = $true }
            { $_ -in "-h", "--help" }  { ShowUsage; return '__help__' }
            default { $positional += $arg }
        }
    }
    if ($positional.Count -gt 0) { $command = $positional[0] }
    # Expose the second positional (if any) for subcommands like `languages [LANG]`.
    $script:CommandArg = if ($positional.Count -gt 1) { $positional[1] } else { '' }
    return $command
}
```

Also add `$script:CommandArg = $false` initialisation alongside the other state in `Reset-DotfileState` in `tests/powershell/helpers.ps1`. Open that file and add the line:

```powershell
function Reset-DotfileState {
    $script:Dry = $false
    $script:Quiet = $false
    $script:Force = $false
    $script:OverwriteAll = $false
    $script:BackupAll = $false
    $script:SkipAll = $false
    $script:CommandArg = ''
}
```

- [ ] **Step 4: Add the `languages` switch arm + ShowUsage update**

Find the main switch in `dotfile.ps1` (around line 584) and add the languages arm before `default`:

```powershell
    switch ($command) {
        "all"       { SetupDotfiles }
        "packages"  { InstallPackages }
        "extras"    { InstallExtras }
        "symlinks"  { SetupSymlinks }
        "languages" { Install-Languages -Target $script:CommandArg }
        "verify"    { Verify }
        default     { Fail "Unknown command: $command"; ShowUsage }
    }
```

In `ShowUsage` (the heredoc around line 535), add a `languages` line in the Commands block:

```powershell
function ShowUsage {
    Write-Host @"
Usage: dotfile.ps1 [OPTIONS] [COMMAND]

Commands:
  all         Run full setup (default)
  packages    Install system packages only
  extras      Install fonts
  symlinks    Create symlinks only
  languages [LANG]  Install language toolchains (gleam). LANG selects one.
  verify      Verify installation

Options:
  -d, --dry     Dry run (no changes made)
  -f, --force   Overwrite existing files without prompting
  -q, --quiet   Only show errors
  -h, --help    Show this help message
"@
}
```

- [ ] **Step 5: Manual syntax check**

Confirm:
- `$script:CommandArg` is set unconditionally in `ParseArgs` (always to either the second positional or empty string), so the dispatch can read it without null checks.
- `Install-Languages -Target $script:CommandArg` correctly forwards the empty-string case to the `'all'` arm via the `{ $_ -in @('all', '', 'gleam') }` switch condition.
- `Reset-DotfileState` in helpers.ps1 includes the new `$script:CommandArg` reset line so tests don't see leaked state.

- [ ] **Step 6: Commit**

```bash
git add dotfile.ps1 tests/powershell/test_gleam.ps1 tests/powershell/test_args.ps1 tests/powershell/helpers.ps1
git commit -m "Wire languages subcommand into dotfile.ps1"
```

---

## Task 13: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Edit the Key Commands line**

In `CLAUDE.md`, find the line:

```
dotfile languages [LANG]     # Install language toolchains (zig, odin)
```

Replace with:

```
dotfile languages [LANG]     # Install language toolchains (zig, odin, gleam)
```

- [ ] **Step 2: Verify**

```bash
grep -n 'languages \[LANG\]' CLAUDE.md
```
Expected: shows the updated line with `(zig, odin, gleam)`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Document Gleam in CLAUDE.md Key Commands"
```

---

## Task 14: Full bash test sweep

**Files:** none (verification only)

- [ ] **Step 1: Run --no-docker**

```bash
bash tests/bash/runner.sh --no-docker
```
Expected: ~204 passed / 1 failed (1 is the pre-existing `test_dotfile_symlinks_command_mac` worktree-path-brittle test).

- [ ] **Step 2: Run Docker**

```bash
bash tests/bash/runner.sh
```
Expected: ~204 passed / 0 failed (Docker doesn't hit the path-brittle case).

- [ ] **Step 3: If anything fails, fix the underlying cause**

Most likely failure modes:
- `ensure_*` test that didn't shadow `command` correctly leaks to a real apt/pacman/brew call.
- Stale stub from one test affecting the next (subshell isolation should handle this — if it doesn't, suspect an `export` that escaped).

Do NOT loosen test assertions to make them pass.

- [ ] **Step 4: No commit**

This task ends when both runs are green.

---

## Task 15: Manual smoke test (Linux on Arch host)

**Files:** none (manual verification only)

The download / SHA / extract / atomic swap / cleanup paths can't be unit-tested. Run these manually before considering the bash side done.

**Note:** Erlang and rebar3 are heavyweight installs (~150MB combined). Run the smoke test in a deliberate session.

- [ ] **Step 1: Fresh install**

```bash
rm -rf "$HOME"/.local/gleam-* "$HOME/.local/bin/gleam"
bash ./dotfile languages gleam
"$HOME/.local/bin/gleam" --version
erl -eval 'erlang:display(ok), halt().' -noshell
rebar3 --version
```

Expected:
- `gleam --version` prints `gleam <tag>` matching https://github.com/gleam-lang/gleam/releases/latest
- `erl` prints `ok` (Erlang is installed and working)
- `rebar3 --version` prints rebar3 version

- [ ] **Step 2: Re-install is idempotent**

```bash
bash ./dotfile languages gleam
```

Expected: `Already installed Gleam <tag>`. No new files in `~/.local/gleam-*`.

- [ ] **Step 3: Update no-ops on the latest version**

```bash
bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_gleam'
```

Expected: `Installing Gleam...` then `Already installed Gleam <tag>`.

- [ ] **Step 4: Update ignores foreign installs**

```bash
mv "$HOME/.local/bin/gleam" "$HOME/.local/bin/gleam.ours"
touch "$HOME/.local/gleam-foreign-test"
ln -s "$HOME/.local/gleam-foreign-test" "$HOME/.local/bin/gleam"
bash -c 'source scripts/utils.sh && source scripts/platform.sh && source scripts/packages.sh && source scripts/languages.sh && DRY=false QUIET=false FORCE=false update_gleam' 2>&1 | grep -i gleam || echo "(no gleam output — as expected)"
rm -f "$HOME/.local/bin/gleam" "$HOME/.local/gleam-foreign-test"
mv "$HOME/.local/bin/gleam.ours" "$HOME/.local/bin/gleam"
```

Expected: `(no gleam output — as expected)`.

- [ ] **Step 5: Umbrella runs all three languages**

```bash
bash ./dotfile languages
```

Expected: `Installing Zig... / Already installed Zig <ztag>` + `Installing Odin... / Already installed Odin <otag>` + `Installing Gleam... / Already installed Gleam <gtag>`.

- [ ] **Step 6: No commit**

Once steps 1–5 pass, the bash side is done.

---

## Task 16: Windows smoke test (DEFERRED)

**Files:** none (cannot be run from this Arch host)

When next on Windows, run this sequence in PowerShell:

```powershell
# Step 1: Fresh install
Remove-Item -Recurse -Force $env:LOCALAPPDATA\Programs\gleam-* -ErrorAction SilentlyContinue
Remove-Item -Force $env:LOCALAPPDATA\Programs\gleam -ErrorAction SilentlyContinue
.\dotfile.ps1 languages gleam
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
gleam --version
erl -eval 'erlang:display(ok), halt().' -noshell
rebar3 --version

# Step 2: Re-install short-circuits
.\dotfile.ps1 languages gleam   # expect "Already installed Gleam ..."

# Step 3: Run the PowerShell test suite
pwsh tests/powershell/runner.ps1 test_gleam.ps1
pwsh tests/powershell/runner.ps1 test_args.ps1
```

Document any failures and address them in a follow-up branch.

- [ ] **Step 1: Note that this task is deferred**

This task marker exists so the deferred Windows verification doesn't get forgotten. Do not mark complete until the Windows smoke + PS test runs pass on a real Windows machine.

---

## Self-review notes

- **Spec coverage:** Every function in the spec maps to a task. Bash inventory (7 functions) → Tasks 1–7. Bash umbrellas → Task 8. PowerShell inventory (8 functions + dispatch + usage) → Tasks 9–12. CLAUDE.md → Task 13. Tests → woven into each function task. Bash smoke → Task 15. Windows smoke → Task 16 (deferred).
- **Placeholder scan:** No "TBD" / "implement later" / "appropriate error handling". Every step has runnable code, exact commands, or concrete edits.
- **Type / name consistency:** `gleam_target_triple`, `gleam_latest_release`, `gleam_current_installed_version`, `ensure_erlang`, `ensure_rebar3`, `install_gleam`, `update_gleam` consistent across bash. PascalCase counterparts (`Get-GleamTargetTriple`, `Install-Gleam`, etc.) consistent across PowerShell. Symlink layouts (`~/.local/gleam-<tag>/gleam` and `%LOCALAPPDATA%\Programs\gleam-<tag>\gleam.exe`) consistent. Asset names `gleam-<tag>-<triple>.tar.gz` (Linux/Mac) and `gleam-<tag>-<triple>.zip` (Windows) consistent.
- **One thing to flag during execution:** Task 12 changes the public-ish surface of `ParseArgs` in `dotfile.ps1` by adding a `$script:CommandArg` side-effect. This is necessary for `languages [LANG]` to work; existing callers (which only read the return value) are unaffected. The new test in `test_args.ps1` locks this in.
