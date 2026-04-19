# Gleam language install — design spec

**Date:** 2026-04-18
**Status:** Approved (pending user spec review)
**Scope:** Add Gleam as the third language under `dotfile languages [LANG]`. First language with cross-platform reach: Linux, macOS, AND Windows. Auto-installs Erlang/OTP and rebar3 dependencies.

## Goal

Install the latest Gleam release from GitHub into a versioned per-user directory on all three OSes:
- Linux/macOS: `~/.local/gleam-<tag>/gleam` + symlink at `~/.local/bin/gleam`.
- Windows: `%LOCALAPPDATA%\Programs\gleam-<tag>\gleam.exe` + junction at `%LOCALAPPDATA%\Programs\gleam` on user PATH.

Auto-install Erlang/OTP and rebar3 via the platform's package manager so `gleam build` works out of the box.

## Non-goals

- Pinning to a specific Gleam tag (always installs `releases/latest`).
- Pinning Erlang or rebar3 versions (whatever the platform PM ships).
- sigstore/cosign signature verification (Gleam publishes `.sigstore` files, but cosign is heavy; SHA-256 from the same GitHub API JSON is the integrity check).
- Replacing system / brew / scoop installs of Gleam, Erlang, or rebar3 (foreign installs left alone, detected via the same symlink-target rule used for Zig and Odin).
- Linux distros other than Debian/Arch.
- Windows arch other than x86_64.

## CLI surface

**Linux/macOS** (existing umbrella, gains `gleam` arm):

```
dotfile languages           # install zig + odin + gleam
dotfile languages gleam     # install only gleam (and Erlang + rebar3 deps)
dotfile update              # update all three, only acting on installs we own
```

**Windows** (new — Windows side has no `languages` subcommand today):

```
dotfile.ps1 languages          # install gleam (only language wired into Windows for now)
dotfile.ps1 languages gleam    # same
```

## Files added / changed

| File | Action | Responsibility |
|---|---|---|
| `scripts/languages.sh` | Modify | Add `gleam_target_triple`, `gleam_latest_release`, `gleam_current_installed_version`, `ensure_erlang`, `ensure_rebar3`, `install_gleam`, `update_gleam`. Extend `install_languages` and `update_languages`. |
| `dotfile.ps1` | Modify | Add `Get-GleamTargetTriple`, `Get-GleamLatestRelease`, `Get-GleamCurrentInstalledVersion`, `Install-Erlang`, `Install-Rebar3`, `Install-Gleam`, `Update-Gleam`, `Install-Languages`. Add `languages` to CLI dispatch and `ShowUsage`. |
| `tests/bash/test_languages.sh` | Modify | ~17 new/changed tests covering all the new bash functions and umbrella extensions. |
| `tests/powershell/test_gleam.ps1` | Create | PowerShell tests covering Get-* helpers, Install-Gleam dry-run, Install-Languages dispatch. |
| `tests/powershell/test_args.ps1` | Modify | Add a CLI dispatch test for `dotfile.ps1 languages` (parses, exits 0 in dry-equivalent if such a flag exists; otherwise just confirms it's a recognised verb). |
| `CLAUDE.md` | Modify | Update existing `dotfile languages [LANG]` line to mention `gleam` alongside `zig, odin`. |

## Asset name → triple mapping

| `uname -s` × `uname -m` (or Windows) | Triple | Suffix |
|---|---|---|
| Linux × `x86_64` | `x86_64-unknown-linux-musl` | `.tar.gz` |
| Linux × `aarch64` / `arm64` | `aarch64-unknown-linux-musl` | `.tar.gz` |
| Darwin × `x86_64` | `x86_64-apple-darwin` | `.tar.gz` |
| Darwin × `arm64` / `aarch64` | `aarch64-apple-darwin` | `.tar.gz` |
| Windows × `x86_64` (only) | `x86_64-pc-windows-msvc` | `.zip` |

`musl` chosen for Linux: statically linked, no glibc version coupling.
Asset name format: `gleam-<tag>-<triple><suffix>` (e.g. `gleam-v1.15.4-x86_64-unknown-linux-musl.tar.gz`).

## Install layout

### Linux / macOS

```
~/.local/gleam-<tag>/gleam            # versioned install dir + binary
~/.local/bin/gleam                    # symlink → ~/.local/gleam-<tag>/gleam
```

Important: Gleam tarballs extract **flat** — just the `gleam` binary at the archive root, no parent directory. The install step creates the versioned dir and moves the binary into it.

### Windows

```
%LOCALAPPDATA%\Programs\gleam-<tag>\gleam.exe       # versioned install dir + binary
%LOCALAPPDATA%\Programs\gleam\                      # junction → versioned dir
```

`%LOCALAPPDATA%\Programs\gleam` (the junction path) is added to user PATH via the existing `AddToUserPath` helper.

## Linux / macOS function inventory (`scripts/languages.sh`)

### `gleam_target_triple`

```bash
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

### `gleam_latest_release`

Same optional-JSON-arg pattern as `odin_latest_release`. URL: `https://api.github.com/repos/gleam-lang/gleam/releases/latest`.

### `gleam_current_installed_version`

Identical shape to `odin_current_installed_version` with `gleam` substituted. Reads `~/.local/bin/gleam`, parses `~/.local/gleam-<tag>/gleam`.

### `ensure_erlang`

```bash
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

### `ensure_rebar3`

Same shape as `ensure_erlang`. Detection: `command -v rebar3`. Package name `rebar3` on all three platforms.

### `install_gleam`

```text
1. info "Installing Gleam..."
2. ensure_jq                           # for parsing release JSON
3. ensure_erlang                       # runtime dep
4. ensure_rebar3                       # build helper
5. triple = gleam_target_triple
6. if DRY: dry-run path, return
7. release_json = gleam_latest_release
8. tag = jq '.tag_name'
9. asset = "gleam-${tag}-${triple}.tar.gz"
10. current = gleam_current_installed_version
11. if current == tag: success "Already installed Gleam $tag"; return
12. digest = jq for asset's .digest, strip "sha256:" prefix; format guard
13. asset_url = jq for asset's .browser_download_url
14. tmpdir, RETURN trap
15. curl -sfL → tar_path; fail on download error
16. _sha256 tar_path == expected_sha; fail on mismatch
17. tar -xf tar_path -C extract_dir
18. **Differs from Zig/Odin:** assert extract_dir contains a file named `gleam` (the binary). Fail loudly if not.
19. mkdir -p target_dir = $HOME/.local/gleam-$tag
20. mv extract_dir/gleam → target_dir/gleam
21. mkdir -p $HOME/.local/bin; ln -sfn target_dir/gleam → $HOME/.local/bin/gleam
22. cleanup old ~/.local/gleam-*/ that aren't target_dir
23. success "Installed Gleam $tag"
```

The flat-tarball difference (step 18) replaces the `find -mindepth 1 -maxdepth 1 -type d` single-dir guard with a single-binary guard.

### `update_gleam`

```bash
update_gleam() {
  local current
  current="$(gleam_current_installed_version)"
  [[ -z "$current" ]] && return 0
  install_gleam
}
```

### Umbrella changes

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

update_languages() {
  update_zig
  update_odin
  update_gleam
}
```

## Windows function inventory (`dotfile.ps1`)

### `Get-GleamTargetTriple`

```powershell
function Get-GleamTargetTriple {
  $arch = [System.Environment]::Is64BitOperatingSystem ? "x86_64" : $null
  if (-not $arch) { Fail "Unsupported architecture for Gleam (need 64-bit)" }
  return "$arch-pc-windows-msvc"
}
```

(Single arch supported. ARM Windows could be added later by inspecting `[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture`, but YAGNI now.)

### `Get-GleamLatestRelease`

```powershell
function Get-GleamLatestRelease {
  param([string]$Json = $null)
  if (-not $Json) {
    $Json = InvokeRestMethodRetry -Uri "https://api.github.com/repos/gleam-lang/gleam/releases/latest" | ConvertTo-Json -Depth 100 -Compress
  }
  return $Json
}
```

The wrapper around `InvokeRestMethodRetry` mirrors the Bash optional-arg pattern.

### `Get-GleamCurrentInstalledVersion`

Reads the junction at `%LOCALAPPDATA%\Programs\gleam`. If it's a junction whose target matches `%LOCALAPPDATA%\Programs\gleam-<tag>`, return `<tag>`. Otherwise return empty.

```powershell
function Get-GleamCurrentInstalledVersion {
  $junction = Join-Path $env:LOCALAPPDATA "Programs\gleam"
  if (-not (Test-Path $junction)) { return "" }
  $item = Get-Item -LiteralPath $junction -ErrorAction SilentlyContinue
  if (-not $item.Target) { return "" }   # not a junction/symlink
  $target = $item.Target | Select-Object -First 1
  $prefix = Join-Path $env:LOCALAPPDATA "Programs\gleam-"
  if ($target.StartsWith($prefix)) {
    return $target.Substring($prefix.Length)
  }
  return ""
}
```

### `Install-Erlang` and `Install-Rebar3`

Each: `if Get-Command <bin> not found, scoop install <pkg>` (with appropriate package names — `main/erlang` and `main/rebar3`, both in the default scoop main bucket). Respects `$script:Dry`.

### `Install-Gleam`

```text
1. Info "Installing Gleam..."
2. Install-Erlang
3. Install-Rebar3
4. $triple = Get-GleamTargetTriple
5. if $script:Dry: log + return
6. $release = Get-GleamLatestRelease | ConvertFrom-Json
7. $tag = $release.tag_name
8. $asset = "gleam-$tag-$triple.zip"
9. $current = Get-GleamCurrentInstalledVersion
10. if $current -eq $tag: Success "Already installed Gleam $tag"; return
11. extract digest from $release.assets, strip "sha256:" prefix, format guard
12. $url = matching $release.assets[].browser_download_url
13. $tmp = New-TemporaryFile renamed to .zip
14. Invoke-WebRequest -Uri $url -OutFile $tmp
15. Get-FileHash -Path $tmp -Algorithm SHA256 must equal expected; fail otherwise
16. $extract = New temp dir; Expand-Archive -Path $tmp -DestinationPath $extract
17. Assert $extract\gleam.exe exists; fail otherwise
18. $target = "$env:LOCALAPPDATA\Programs\gleam-$tag"; remove if exists; New-Item -ItemType Directory; Move-Item $extract\gleam.exe → $target\gleam.exe
19. Replace junction $env:LOCALAPPDATA\Programs\gleam → $target (atomic-ish: remove old junction, New-Item -ItemType Junction)
20. AddToUserPath "$env:LOCALAPPDATA\Programs\gleam"
21. Cleanup old "$env:LOCALAPPDATA\Programs\gleam-*" dirs that aren't $target
22. Cleanup $tmp + $extract
23. Success "Installed Gleam $tag"
```

### `Update-Gleam`

```powershell
function Update-Gleam {
  if (-not (Get-GleamCurrentInstalledVersion)) { return }
  Install-Gleam
}
```

### `Install-Languages`

```powershell
function Install-Languages {
  param([string]$Target = "all")
  switch ($Target) {
    { $_ -in @("all", "", "gleam") } { Install-Gleam }
    default { Fail "Unknown language: $Target" }
  }
}
```

(Only Gleam wired into Windows for now; Zig and Odin can be added later if desired — Windows has scoop entries for Zig already, no Odin.)

### CLI dispatch

In `dotfile.ps1`'s main switch, add:
```powershell
"languages" {
  $lang = if ($RemainingArgs.Count -ge 2) { $RemainingArgs[1] } else { "" }
  Install-Languages -Target $lang
}
```

In `ShowUsage`, add line:
```
  languages [LANG]    Install language toolchains (gleam). LANG selects one.
```

## Tests

### Bash (`tests/bash/test_languages.sh`)

Each function gets the same coverage shape as Odin's tests:
- 5 triple tests (Linux/Mac × supported archs + 1 unsupported)
- 2 latest-release tests (passed-arg vs fetched)
- 3 current-installed-version tests (none / ours / foreign)
- 4 ensure_erlang tests (already-present noop + dry-run per platform), using the same `command()` shadow trick
- 4 ensure_rebar3 tests (same shape)
- 2 install_gleam tests (dry-run + already-installed)
- 3 update_gleam tests
- Tighten `test_install_languages_dry_run` and `test_install_languages_all_arg` to assert `Installing Gleam` alongside Zig + Odin
- Add `test_install_languages_gleam_only_arg` (and assert NO Zig/Odin output for clean isolation)

Network-dependent download/SHA/extract paths not unit-tested — manual smoke covers them.

### PowerShell (`tests/powershell/test_gleam.ps1`) — new file

Existing test pattern (per `CLAUDE.md`): source `tests/powershell/helpers.ps1`, dot-source `dotfile.ps1 -NoMain` to load functions without main dispatch.

| Test | Purpose |
|---|---|
| `Test-GetGleamTargetTriple` | On 64-bit Windows: returns `x86_64-pc-windows-msvc`. |
| `Test-GetGleamLatestRelease-UsesPassedJson` | Pass JSON arg → returns it; `InvokeRestMethodRetry` not called (verified via mock function). |
| `Test-GetGleamCurrentInstalledVersion-None` | No junction → empty. |
| `Test-GetGleamCurrentInstalledVersion-Ours` | Pre-create versioned dir + junction → returns the tag. |
| `Test-GetGleamCurrentInstalledVersion-Foreign` | Junction points to non-`gleam-*` dir → empty. |
| `Test-InstallGleam-DryRun` | `$script:Dry = $true` → no network/disk; expected log lines. |
| `Test-InstallLanguages-DispatchesGleam` | `Install-Languages gleam` reaches `Install-Gleam` (verified by mocking the latter). |
| `Test-InstallLanguages-Unknown-Fails` | `Install-Languages java` → throws. |

### CLI dispatch test addition

`tests/powershell/test_args.ps1` gains: parsing `languages` returns the right command verb.

### Manual smoke tests

**Linux (Arch x86_64):**
1. Fresh: `rm -rf ~/.local/gleam-* ~/.local/bin/gleam && bash ./dotfile languages gleam && ~/.local/bin/gleam --version` → matches latest GitHub tag.
2. Re-install: short-circuits with "Already installed Gleam <tag>".
3. `update_gleam` real call short-circuits when current.
4. Foreign install: replace symlink with one pointing at `/tmp/fake-gleam`, `update_gleam` is silent. Restore.
5. Umbrella runs all three (`bash ./dotfile languages` → Zig + Odin + Gleam each short-circuit).
6. Erlang & rebar3 actually present after install (`erl -version`, `rebar3 -v`).

**Windows (deferred):** Same set on Windows when next available — verify junction created, PATH updated, `gleam --version` works in a fresh shell.

## Error handling

- `set -eo pipefail` on bash side; `$ErrorActionPreference = "Stop"` already set in `dotfile.ps1`.
- All download / SHA / extract failures call `fail` (bash) or `Fail` (PowerShell).
- SHA-256 mismatch fails loudly with the expected vs got values.
- Trap on bash side cleans up tmpdir on RETURN; PowerShell side uses `try/finally` for cleanup.

## Open questions

None. All decisions resolved during brainstorming.

## Out of scope / future work

- Adding Zig + Odin to the Windows side of `Install-Languages` (Zig already comes via scoop in `InstallPackages`; Odin has no scoop manifest yet).
- ARM Windows support.
- sigstore/cosign verification.
- A `dotfile uninstall <language>` complement.
- A `dotfile.ps1 update` subcommand to mirror the Linux update flow (Windows currently treats `dotfile.ps1 packages` as the upgrade entry point).
