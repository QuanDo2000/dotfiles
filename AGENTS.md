# Dotfiles Agent Guide

Personal Linux/macOS/Windows provisioning. Unix uses Nix/Home Manager; Windows uses `dotfile.ps1`.

## Commands

- `dotfile`: full setup; `packages`: prerequisites; `upgrade`: native package upgrades.
- `dotfile update`: routine refresh of all pins, native prerequisites, and profile activation; `update ai`: AI-only update.
- `dotfile doctor`: health checks; `obsidian`: Sync bootstrap; `obsidian-headless`: pinned-release update.
- `dotfile -d <command>`: dry run; `-f`: force overwrite.
- Windows retains its own `verify` command and runs symlink/extra setup inside `all`.

Git and JJ default to SSH signing with `~/.ssh/id_ed25519.pub`; Git commits/tags require signing and JJ uses `signing.behavior = "own"`. This public path does not provision a private key. On failure, distinguish effective backend/path configuration, availability of the matching private key through the intended agent, and agent unlock state. Ask the user to restore/unlock their intended existing identity; never select the first key, create keys, change authentication, or bypass signing. Config checks are not cryptographic verification; verify actual Git/JJ signatures separately before delivery.

Git's `~/.gitconfig.local` include follows managed defaults (and the Windows include), so user-owned values override them; repository config has higher precedence. JJ uses native user `conf.d/*.toml` overrides after `config.toml`, then repository config; preserve existing machine-local settings, including `keep`. Never edit live overrides as part of a source-default change. For explicitly chosen OpenPGP overrides and backend-specific diagnosis, see `config/shared/ai/skills/dotfiles-health-checks/references/headless-git-publishing.md`. GPG unlock probes do not diagnose SSH signing.

## Ownership and Entry Points

`dotfile` sources modular scripts: `utils.sh` (logging), `packages.sh` (platform prerequisites/rebuilds), `releases.sh` (updates), `pins.sh` / `update_pins.py` (verified pin refresh), `doctor.sh` (health), and `obsidian.sh` (interactive Sync setup). Shared flags are exported `DRY`, `QUIET`, and `FORCE`. Windows implementation is in `dotfile.ps1`.

`config/home.nix` owns Unix links and generates `.zshrc` from `config/unix/.zshrc.base`. Layer `config/` children map by basename into `~/.config/`; top-level dotfiles map into `$HOME`, subject to explicit profile gates and exceptions:

- `config/shared/`: cross-platform tools, AI seeds, SSH, Neovim, Obsidian. Unix Git uses Home Manager; shared `.gitconfig` remains for Windows.
- `config/unix/`: shells/tools and profile-gated Linux desktop configs. `config/mac/` and `config/windows/`: platform-specific files.
- `config/nixos/`: physical system; machine values in `config/host.nix`, hardware in `config/hardware-configuration.nix`. NixOS skips imperative package installers.
- `config/nixos-wsl/`: `${hostName}-wsl`, auto-selected by Microsoft WSL kernel detection; excludes physical hardware/bootloader/NVIDIA/desktop configuration.

Shared development tools are the default. NixOS adds desktop/personal apps, Obsidian Sync, and Google Drive. Arch server adds Sync, Drive, and storage backup without desktop/personal apps. Generic Linux/macOS leave optional groups off. Obsidian GUI/settings are personal-only; headless Sync runs on NixOS and Arch server. `packages.sh` uses apt/pacman only for Linux bootstrap, NixOS flakes for rebuilds, and existing or pinned-bootstrap nix-darwin on macOS.

Link only owned files: SSH config and selected Obsidian settings, not entire runtime directories. Leave caches, sessions, credentials, `node_modules`, `skills-lock.json`, and plugin runtime artifacts alone.

## AI Instructions and Skills

`config/shared/ai/AGENTS.md` owns shared Pi instructions; `SOUL.md` owns Hermes policy. Keep common authority/delivery rules aligned. Shared skills under `ai/skills/` install into `~/.agents/skills/` via Home Manager and Windows `InstallAiSkills`; verify native discovery in Pi. Agent-specific tools, memory, UI, hooks, and adapters stay native.

Hermes adaptations under `ai/hermes/skills/` are separate immutable Home Manager links for the default Unix profile. Read `config/shared/ai/hermes/README.md` before changing deployment/updater ownership. Preserve attribution and update boundaries; never edit store targets or force-reset bundled skills. Promote reusable machine-local skills only with explicit approval, complete assets, sanitization, and discovery verification.

## Validation

```bash
nix develop path:. -c bash tests/bash/runner.sh    # pinned Bash suite
bash tests/bash/runner.sh test_platform_packages.sh # focused host run
pwsh tests/powershell/runner.ps1                  # Windows/pwsh suite
./scripts/check.sh                               # full local gate
```

The full gate runs Bash, PowerShell if present, Nix evaluation/builds, and ShellCheck. Preserve check exit status and report unavailable platform coverage.

Prefer a small number of repeatable end-to-end checks through `dotfile` or `dotfile.ps1`, using disposable state. For bug fixes, run the same symptom reproducer against baseline and patched revisions under equivalent conditions: baseline fails, patched passes (A/B regression verification, not statistical experimentation).

Do not add unit tests by default or duplicate E2E assertions. Add a focused test only when an important security, data-loss, rollback, or correctness failure cannot be exercised safely and reliably end to end. Reuse existing checks and run applicable repository gates. Disclose substitutions and unavailable coverage; mock-backed checks are not E2E evidence.
