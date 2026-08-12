# Raw Neovim evaluation

## Scope and method

Baseline snapshot: current live checkout config copied to `/tmp/lazyvim-baseline.izR1UX/nvim` before implementation. Main checkout remained untouched afterward. Raw implementation lives only on branch `raw-neovim-evaluation` in its dedicated worktree.

Measurements use Neovim 0.12.4 on the same machine and installed plugin data. Startup comparison runs `nvim --headless +qa` for 60 paired rounds in seeded randomized order. Clean runs delete each config's isolated XDG cache/state before every sample; warm runs use 5 excluded warmups and stable isolated cache/state. Network access and plugin installation are outside timed commands. Full samples are stored in `/tmp/nvim-comparison.json` during evaluation.

Config size counts tracked `config/shared/config/nvim` files. Lua LOC/bytes count `*.lua`; all bytes include lock/style/ignore files. Plugin count includes enabled Lazy specs on Unix, excluding disabled Nix-managed `lazy.nvim`. Footprint sums `du -sb` for those configured plugin directories; shared parser and Mason tool data are excluded equally.

## Measured result

| Metric | LazyVim baseline | Raw config | Change |
| --- | ---: | ---: | ---: |
| Enabled plugins | 40 | 26 | -14 (-35.0%) |
| Lock entries | 41 | 27 | -14 (-34.1%) |
| Plugin bytes | 124,481,155 | 101,966,876 | -22,514,279 (-18.1%) |
| Lua LOC | 285 | 479 | +194 (+68.1%) |
| Lua bytes | 8,803 | 19,148 | +10,345 (+117.5%) |
| All config bytes | 13,373 | 22,090 | +8,717 (+65.2%) |
| Clean median | 65.529 ms | 49.823 ms | -15.706 ms (-24.0%) |
| Clean mean | 66.837 ms | 51.196 ms | -15.641 ms (-23.4%) |
| Clean p95 | 83.990 ms | 66.726 ms | -17.264 ms (-20.6%) |
| Warm median | 30.707 ms | 26.719 ms | -3.988 ms (-13.0%) |
| Warm mean | 31.856 ms | 27.583 ms | -4.274 ms (-13.4%) |
| Warm p95 | 41.034 ms | 36.515 ms | -4.519 ms (-11.0%) |

## Feature-parity checklist

- [x] Core editing: leader keys, `jk`, clipboard, OSC 52 over SSH, line numbers, undo, search, splits, diagnostics, native comments, folds, and standard buffer/window commands.
- [x] Completion: Blink LSP/path/snippet/buffer completion, auto-insert selection, `<C-e>` cancel, friendly snippets.
- [x] LSP: Bash, JSON/SchemaStore, Lua, Markdown, Nix, TOML, YAML/SchemaStore; diagnostics; definitions/references/implementation/type, hover, rename, code actions; inlay hints remain disabled.
- [x] Formatting: Conform format-on-save and `<leader>cf`; Lua, Markdown/MDX, Nix, then LSP fallback.
- [x] Linting: markdownlint-cli2 and statix on write/insert leave.
- [x] Treesitter: parser install/update plus highlighting/indent for shell, Git, JSON, Lua, Markdown, Nix, TOML, Vim, and YAML.
- [x] Picker/explorer: FFF find/grep on Unix; Snacks fallback on Windows; root/cwd files, grep, buffers, recent files, diagnostics, help, keymaps, and Snacks explorer.
- [x] Git: Gitsigns hunk navigation/stage/reset/preview/blame, Snacks status/diff, Lazygit.
- [x] Terminal/Pi: right-side 80-column Pi terminal, focus/toggle, file/position/selection send, Linux submit, Windows no-auto-submit.
- [x] Sessions: current/last restore and opt-out through persistence.nvim.
- [x] Editing extras with explicit prior opt-in: mini.surround, Yanky history/cycling, Dial increments, mini.ai, hex-color highlights.
- [x] UI: Catppuccin Macchiato, statusline, bufferline, which-key, Snacks notifications.
- [x] Markdown: in-editor render-markdown; browser preview remains intentionally disabled.
- [x] Platform behavior: Home Manager/Nix on Linux/macOS, writable lock and bootstrap on Windows, Unix-only hash-pinned FFF backend.
- [x] Provisioning/update: raw lock seeding, Windows plugin sync, FFF updater path, isolated lock refresh, CI integration.
- [x] Tests/health: raw headless config test, Pi terminal regression, Bash/PowerShell provisioning tests, Windows clean bootstrap integration. Existing doctor behavior remains unchanged; it checks managed links/tools but had no direct LazyVim health probe.

## Deleted as unused framework surface

No repository evidence showed active use, and some entries were nonfunctional without adapters: LazyVim framework, Flash, Trouble, Noice, todo-comments, grug-far, lazydev, Neotest with zero adapters, Treesitter textobjects/autotag, ts-comments, and transitive plenary/nui/nvim-nio. Native Neovim or retained plugins cover current explicit behavior. Re-add only after a concrete workflow and regression check establish a parity gap.

## Recommendation

**Reject replacing LazyVim for now.** Raw config cuts 14 plugins, 22.5 MB, clean-start median by 24.0%, and warm-start median by 13.0%, but owned config grows 68.1% LOC / 65.2% bytes. Runtime gains are real; maintenance and cross-platform ownership also increase sharply. Keep branch as measured prototype unless dependency count and startup latency outweigh framework maintenance. Merge only with explicit acceptance of larger owned config.
