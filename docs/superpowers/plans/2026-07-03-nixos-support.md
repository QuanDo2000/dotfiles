# NixOS Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize NixOS as a platform and let `dotfile packages` reprovision the whole system from a tracked `configuration.nix` via `nixos-rebuild switch`, while symlinks/extras/verify keep working unchanged.

**Architecture:** `detect_platform` gains a `nixos` branch. On NixOS, `install_packages`/`update_packages` dispatch to new `install_nixos`/`update_nixos` functions that symlink the repo's `config/nixos/configuration.nix` into `/etc/nixos/` and run `nixos-rebuild switch` — replacing every imperative `setup_*` installer. App configs stay as symlinked dotfiles. The tracked `.nix` file is a full-desktop starting template; `hardware-configuration.nix` stays machine-generated and git-ignored.

**Tech Stack:** Bash (sourced scripts), NixOS/nixpkgs, the repo's bash test harness under `tests/bash/`.

## Global Constraints

- Bash scripts are POSIX-ish bash 3.2 compatible (macOS ships bash 3.2) — no `mapfile`/`readarray`.
- Every installer/dispatch function respects `DRY`: when `DRY=true`, log but make no changes.
- Logging via `info`/`success`/`fail` from `utils.sh`.
- `detect_platform` returns one of: `nixos`, `debian`, `arch`, `mac`, `unknown`.
- Tests: one `test_<module>.sh` per script; source `helpers.sh`, use `init_test_env`/`cleanup_test_env`, `source_scripts`, `mock_uname`, and the `assert_*` helpers. Failures append to `$ERROR_FILE`.
- Commits are GPG-signed; the user runs `git commit` themselves when the agent cannot sign. Each task's commit step may need to be handed to the user.

---

### Task 1: NixOS platform detection

**Files:**
- Modify: `scripts/platform.sh:12-30` (`detect_platform`)
- Test: `tests/bash/test_platform.sh`

**Interfaces:**
- Produces: `detect_platform` returns `nixos` when the os-release `ID` is `nixos`. Honors an `OS_RELEASE` env override (path to the os-release file, default `/etc/os-release`) so the branch is testable without touching `/etc`.

- [ ] **Step 1: Write the failing test**

Add to `tests/bash/test_platform.sh` (its `setup` already runs `init_test_env` and `source_scripts utils.sh symlinks.sh`; add `platform.sh` is pulled in automatically by `source_scripts`, but add it explicitly for clarity):

```bash
# ---------------------------------------------------------------------------
# detect_platform: NixOS
# ---------------------------------------------------------------------------

test_detect_platform_nixos() {
  source_scripts packages.sh   # pulls in platform.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}

test_detect_platform_nixos_precedes_arch() {
  # A NixOS os-release must not be misread as arch even if ID_LIKE mentions it.
  source_scripts packages.sh
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\nID_LIKE=""\n' > "$osrel"

  local result
  result="$(OS_RELEASE="$osrel" detect_platform)"

  assert_equals "nixos" "$result"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/bash/runner.sh --no-docker test_platform.sh`
Expected: FAIL — `detect_platform` currently reads hardcoded `/etc/os-release` and has no `nixos` branch, so it returns `arch` (the host) or `unknown`.

- [ ] **Step 3: Implement the detection**

Edit `scripts/platform.sh`. Replace the `detect_platform` body's Linux block so it honors `OS_RELEASE` and checks nixos first:

```bash
# Print one of: nixos, debian, arch, mac, unknown
detect_platform() {
  if is_mac; then
    echo "mac"
    return
  fi
  local os_release="${OS_RELEASE:-/etc/os-release}"
  if is_linux && [[ -f "$os_release" ]]; then
    # shellcheck disable=SC1091
    local ID="" ID_LIKE=""
    # shellcheck disable=SC1091
    . "$os_release"
    if [[ "${ID:-}" == "nixos" ]]; then
      echo "nixos"
      return
    fi
    if [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
      echo "debian"
      return
    fi
    if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
      echo "arch"
      return
    fi
  fi
  echo "unknown"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/bash/runner.sh --no-docker test_platform.sh`
Expected: PASS (new nixos tests pass; existing platform tests still pass).

- [ ] **Step 5: Commit**

```bash
git add scripts/platform.sh tests/bash/test_platform.sh
git commit -m "platform: detect nixos, honor OS_RELEASE override"
```

---

### Task 2: NixOS package flow (rebuild) + zsh guard + dispatch

**Files:**
- Modify: `scripts/packages.sh` (add `install_nixos`/`update_nixos`; wire into `install_packages`/`update_packages`; guard `set_zsh_default`)
- Test: `tests/bash/test_packages.sh`, `tests/bash/test_cli.sh`

**Interfaces:**
- Consumes: `detect_platform` returning `nixos` (Task 1); `$DOTFILES_DIR` (exported by the `dotfile` entrypoint / `init_test_env`).
- Produces: `install_nixos` and `update_nixos` — DRY-aware functions that (non-DRY) symlink `$DOTFILES_DIR/config/nixos/configuration.nix` into `/etc/nixos/` and run `nixos-rebuild switch`. `set_zsh_default` becomes a no-op on NixOS.

- [ ] **Step 1: Write the failing tests**

Add to `tests/bash/test_packages.sh`:

```bash
# ---------------------------------------------------------------------------
# NixOS package flow
# ---------------------------------------------------------------------------

test_install_nixos_dry_run() {
  DRY=true
  local output
  output=$(install_nixos 2>&1)

  assert_contains "$output" "NixOS"
  # DRY must not touch the system or invoke the imperative installers.
  assert_not_contains "$output" "nixos-rebuild"
  assert_not_contains "$output" "neovim"
}

test_update_nixos_dry_run() {
  DRY=true
  local output
  output=$(update_nixos 2>&1)

  assert_contains "$output" "NixOS"
  assert_not_contains "$output" "nixos-rebuild"
}

test_install_packages_dispatches_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=true

  local output
  output=$(OS_RELEASE="$osrel" install_packages 2>&1)

  assert_contains "$output" "NixOS"
}

test_set_zsh_default_skips_on_nixos() {
  mock_uname Linux
  local osrel="$TEST_TMPDIR/os-release"
  printf 'ID=nixos\n' > "$osrel"
  DRY=false

  local output
  output=$(OS_RELEASE="$osrel" set_zsh_default 2>&1)

  assert_contains "$output" "declaratively"
}
```

`assert_not_contains` does not exist yet. Add it to `tests/bash/runner.sh` right after `assert_contains` (around line 82), matching that file's indentation and message style:

```bash
assert_not_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  assert_not_contains FAILED: '$haystack' unexpectedly contains '$needle'" >> "$ERROR_FILE"
    fi
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: FAIL — `install_nixos`/`update_nixos` are undefined; `install_packages` has no nixos case; `set_zsh_default` has no nixos guard.

- [ ] **Step 3: Implement the NixOS functions and dispatch**

In `scripts/packages.sh`, add the two functions just above `function update_packages`:

```bash
# Reprovision NixOS from the tracked configuration.nix. Symlinks the repo's
# config into /etc/nixos (leaving the machine-generated
# hardware-configuration.nix untouched) and runs nixos-rebuild switch. On
# NixOS all imperative setup_* installers are skipped — packages come from the
# rebuild. Usage: install_nixos
function install_nixos {
  info "Installing packages for NixOS..."
  if [[ "$DRY" == "false" ]]; then
    local cfg="$DOTFILES_DIR/config/nixos/configuration.nix"
    [[ -f "$cfg" ]] || fail "NixOS config not found: $cfg"
    sudo ln -sfn "$cfg" /etc/nixos/configuration.nix \
      || fail "Failed to link configuration.nix into /etc/nixos"
    sudo nixos-rebuild switch || fail "nixos-rebuild switch failed"
  fi
  success "Finished install for NixOS"
}

# Update NixOS: pull channels and rebuild. Usage: update_nixos
function update_nixos {
  info "Updating packages for NixOS..."
  if [[ "$DRY" == "false" ]]; then
    sudo nixos-rebuild switch --upgrade || fail "nixos-rebuild switch --upgrade failed"
  fi
  success "Finished update for NixOS"
}
```

Add the `nixos` case to `update_packages`:

```bash
function update_packages {
  info "Updating packages..."
  case "$(detect_platform)" in
    nixos)   update_nixos ;;
    debian)  update_debian ;;
    arch)    update_arch ;;
    mac)     update_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac
  success "Finished update"
}
```

Add the `nixos` case to `install_packages`:

```bash
function install_packages {
  info "Installing packages..."
  case "$(detect_platform)" in
    nixos)   install_nixos ;;
    debian)  install_debian ;;
    arch)    install_arch ;;
    mac)     install_mac ;;
    unknown) fail "Unsupported system: $(uname) (could not detect Linux distro)" ;;
  esac

  set_zsh_default
  success "Finished install"
}
```

Guard `set_zsh_default` — add at the very top of the function body, right after `info "Changing default shell to zsh..."`:

```bash
  if [[ "$(detect_platform)" == "nixos" ]]; then
    info "Shell is managed declaratively on NixOS; skipping chsh"
    success "Finished changing zsh as default"
    return
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/bash/runner.sh --no-docker test_packages.sh`
Expected: PASS.

- [ ] **Step 5: Add the CLI dispatch test**

Add to `tests/bash/test_cli.sh`:

```bash
test_packages_nixos_dry() {
  mock_uname Linux
  local osrel="$TEST_HOME/os-release"
  printf 'ID=nixos\n' > "$osrel"

  local output
  output=$(OS_RELEASE="$osrel" bash "$DOTFILE_CMD" --dry packages 2>&1)
  assert_contains "$output" "NixOS"

  # Don't leak the uname mock into later tests in this file.
  unset -f uname 2>/dev/null || true
  unset __MOCK_UNAME
}
```

- [ ] **Step 6: Run the CLI tests**

Run: `bash tests/bash/runner.sh --no-docker test_cli.sh`
Expected: PASS. (The bash suite runs on Linux — `is_linux` is true — so the `OS_RELEASE` override alone yields `nixos`.)

- [ ] **Step 7: Commit**

```bash
git add scripts/packages.sh tests/bash/test_packages.sh tests/bash/test_cli.sh tests/bash/runner.sh
git commit -m "packages: reprovision NixOS via nixos-rebuild switch"
```

---

### Task 3: Tracked configuration.nix template

**Files:**
- Create: `config/nixos/configuration.nix`
- Modify: `.gitignore` (ignore `config/nixos/hardware-configuration.nix`)

**Interfaces:**
- Consumes: referenced by `install_nixos` (Task 2) at `$DOTFILES_DIR/config/nixos/configuration.nix`.
- Produces: a full-desktop NixOS system config template that `imports = [ ./hardware-configuration.nix ]`.

- [ ] **Step 1: Write the config template**

Create `config/nixos/configuration.nix`. Per-machine knobs are marked `# EDIT:`.

```nix
# Preliminary NixOS system configuration for these dotfiles.
#
# This is a STARTING TEMPLATE — the `# EDIT:` lines below are per-machine and
# must be tuned on a real box. `dotfile packages` symlinks this file to
# /etc/nixos/configuration.nix and runs `nixos-rebuild switch`.
#
# hardware-configuration.nix is machine-generated (`nixos-generate-config`),
# per-machine, and git-ignored. Generate it once on the target machine.
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # --- System core ---------------------------------------------------------
  system.stateVersion = "24.11";              # EDIT: match the install's NixOS release
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Asia/Ho_Chi_Minh";         # EDIT: your timezone
  i18n.defaultLocale = "en_US.UTF-8";
  networking.hostName = "nixos";              # EDIT: your hostname
  networking.networkmanager.enable = true;

  # --- Boot ----------------------------------------------------------------
  boot.loader.systemd-boot.enable = true;     # EDIT: use GRUB instead if needed
  boot.loader.efi.canTouchEfiVariables = true;

  # --- User ----------------------------------------------------------------
  programs.zsh.enable = true;
  users.users.quan = {                        # EDIT: your username
    isNormalUser = true;
    description = "Quan Do";                   # EDIT
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.zsh;
  };

  # --- Desktop: Hyprland + greetd login ------------------------------------
  programs.hyprland.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
      user = "greeter";
    };
  };

  # --- Input method: fcitx5 ------------------------------------------------
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-unikey ];   # EDIT: your input addons
  };

  # --- Fonts ---------------------------------------------------------------
  fonts.packages = with pkgs; [ nerd-fonts.fira-code ];

  # --- Packages ------------------------------------------------------------
  # Ported from ARCH_PACKAGES in scripts/packages.sh. App config files stay as
  # symlinked dotfiles (dotfile symlinks); NixOS only installs the binaries.
  environment.systemPackages = with pkgs; [
    git
    zsh
    tmux
    neovim
    fzf
    fd
    ripgrep
    lazygit
    jujutsu
    starship
    zoxide
    gnupg
    wl-clipboard
    openssh
    unzip
    fontconfig
    tree-sitter
    lua5_1
    luarocks
    waybar
    ghostty
    opencode
  ];
}
```

- [ ] **Step 2: Git-ignore the machine-generated hardware config**

Append to `.gitignore`:

```gitignore
# NixOS hardware config is machine-generated and per-machine
config/nixos/hardware-configuration.nix
```

- [ ] **Step 3: Sanity-check the Nix syntax (only if nix is available)**

Run: `command -v nix-instantiate >/dev/null && nix-instantiate --parse config/nixos/configuration.nix >/dev/null && echo PARSE_OK || echo "nix not present — skipping parse check"`
Expected: `PARSE_OK` on a machine with nix; otherwise the skip message. (This template imports `./hardware-configuration.nix`, which won't exist in the repo — `--parse` only checks syntax and does not resolve imports, so it still passes.)

- [ ] **Step 4: Commit**

```bash
git add config/nixos/configuration.nix .gitignore
git commit -m "nixos: add full-desktop configuration.nix template"
```

---

### Task 4: Documentation

**Files:**
- Modify: `CLAUDE.md` (Dotfile Layers section), `README.md` if it lists platforms

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: docs describing the `nixos` layer and the rebuild flow.

- [ ] **Step 1: Document the NixOS layer in CLAUDE.md**

In `CLAUDE.md`, under the "Dotfile Layers" list, add an entry describing `config/nixos/`:

```markdown
5. **config/nixos/** — NixOS-only. `configuration.nix` is a tracked full-desktop
   system config; `dotfile packages` symlinks it to `/etc/nixos/configuration.nix`
   and runs `nixos-rebuild switch`. `hardware-configuration.nix` is machine-generated
   and git-ignored. App config files (hyprland, waybar, etc.) are NOT ported into
   Nix — they stay symlinked dotfiles via `dotfile symlinks`. On NixOS the imperative
   `setup_*` installers are skipped; packages come from the rebuild.
```

Also update the "Print one of: debian, arch, mac, unknown" mention if the docs reference `detect_platform`'s outputs, to include `nixos`.

- [ ] **Step 2: Run the full test suite**

Run: `bash tests/bash/runner.sh --no-docker`
Expected: all suites PASS.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: describe NixOS layer and rebuild flow"
```

---

## Self-Review

**Spec coverage:**
- Platform detection (`nixos` branch) → Task 1. ✓
- Tracked `configuration.nix`, full desktop, hardware config git-ignored → Task 3. ✓
- `dotfile packages` symlinks config + `nixos-rebuild switch`; imperative installers skipped → Task 2. ✓
- `set_zsh_default` skip on NixOS → Task 2. ✓
- symlinks/extras/verify unchanged → no task needed (nothing changes; verified by full suite in Task 4). ✓
- Tests (platform, packages, cli) → Tasks 1, 2. ✓
- Classic non-flake config → Task 3 (flakes feature enabled but not used). ✓

**Placeholder scan:** No TBD/TODO. Per-machine `# EDIT:` markers in the `.nix` template are deliberate calibration knobs (the spec calls them out as required per-machine tuning), not plan placeholders — every step has concrete content.

**Type consistency:** `detect_platform` → `nixos` string used identically in Tasks 1, 2, 3-doc. `install_nixos`/`update_nixos` names consistent across definition (Task 2 Step 3) and dispatch. `OS_RELEASE` env var name consistent across Tasks 1–2. `assert_not_contains` defined in Task 2 Step 1 before use.

## Out of scope (per spec)
Flakes, porting app configs into Nix modules, home-manager, boot-testing on real hardware.
