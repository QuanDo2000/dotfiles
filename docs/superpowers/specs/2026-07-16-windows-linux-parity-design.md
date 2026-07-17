# Windows/Linux Installation Parity

## Scope

Bring the Windows installer to functional parity with the Unix lifecycle while keeping Windows-native package managers and excluding Linux-only desktop services, zsh/tmux, Obsidian Headless, and FFF.

## Design

- One Winget manifest and one Scoop manifest drive installation and health checks.
- doctor verifies exact managed package identities, required public commands, tracked links, and mutable configuration; verify remains an alias.
- Setup and update run doctor after successful mutation.
- Package and AI installers run without blanket elevation. Symlink creation first uses Developer Mode and elevates only the individual link operation if Windows rejects it for privilege.
- Scoop owns FiraCode, jq, and ast-grep. Winget owns the existing CLI set plus Python 3.14, which runs the existing seed scripts.
- Update covers Winget, managed Scoop packages, Node LTS, Codex, Pi, codebase-memory-mcp, and LazyVim.
- Pi comes from @earendil-works/pi-coding-agent. AI installers succeed only when their public command is discoverable afterward.
- Windows links stable Neovim files individually; lazyvim.json is writable and reconciled with the existing lazyvim.py merger.
- Pi settings and MCP configuration are writable seeds using existing pi.py behavior. FFF and global AGENTS linking remain disabled.

## Verification

Each behavior receives a focused PowerShell regression test with a red/green run. Final verification runs the full PowerShell suite, git diff --check, and read-only doctor.
