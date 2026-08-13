# Raw Neovim evaluation

## Scope and method

Baseline snapshot: current live checkout config copied to `/tmp/lazyvim-baseline.izR1UX/nvim` before implementation. Main checkout remained untouched afterward. Raw implementation lives only on branch `raw-neovim-evaluation` in its dedicated worktree.

Measurements use Neovim 0.12.4 on the same machine and installed plugin data. Startup comparison runs `nvim --headless +qa` for 60 paired rounds in seeded randomized order. Clean runs delete each config's isolated XDG cache/state before every sample; warm runs use 5 excluded warmups and stable isolated cache/state. Network access and plugin installation are outside timed commands. Full samples are stored in `/tmp/nvim-comparison.json` during evaluation. Results below describe the initial parity snapshot; later pruning is tracked by tests and the lock file, not retroactively mixed into these benchmark numbers.

Config size counts tracked `config/shared/config/nvim` files. Lua LOC/bytes count `*.lua`; all bytes include lock/style/ignore files. Plugin count includes enabled Lazy specs on Unix, excluding disabled Nix-managed `lazy.nvim`. Footprint sums `du -sb` for those configured plugin directories; shared parser and Mason tool data are excluded equally.

## Measured result

| Metric | LazyVim baseline | Raw config | Change |
| --- | ---: | ---: | ---: |
| Enabled plugins | 40 | 35 | -5 (-12.5%) |
| Lock entries | 41 | 36 | -5 (-12.2%) |
| Plugin bytes | 124,481,155 | 113,214,085 | -11,267,070 (-9.1%) |
| Lua LOC | 285 | 806 | +521 (+182.8%) |
| Lua bytes | 8,803 | 43,211 | +34,408 (+390.9%) |
| All config bytes | 13,373 | 46,752 | +33,379 (+249.6%) |
| Clean median | 60.595 ms | 51.279 ms | -9.317 ms (-15.4%) |
| Clean mean | 61.906 ms | 51.932 ms | -9.974 ms (-16.1%) |
| Clean p95 | 71.503 ms | 59.320 ms | -12.183 ms (-17.0%) |
| Warm median | 27.476 ms | 26.807 ms | -0.669 ms (-2.4%) |
| Warm mean | 28.821 ms | 27.976 ms | -0.845 ms (-2.9%) |
| Warm p95 | 37.226 ms | 35.457 ms | -1.770 ms (-4.8%) |

## Feature-parity checklist

- [x] Core editing: leader keys, `jk`, clipboard, OSC 52 over SSH, line numbers, undo, search, splits, diagnostics, native comments, folds, and standard buffer/window commands.
- [x] Completion: Blink LSP/path/snippet/buffer completion, auto-insert selection, and `<C-e>` cancel; the optional friendly-snippets collection is omitted.
- [x] LSP: Bash, JSON/SchemaStore, Lua, Markdown, Nix, TOML, YAML/SchemaStore; diagnostics; definitions/references/implementation/type, hover, rename, code actions; inlay hints remain disabled.
- [x] Formatting: Conform format-on-save and `<leader>cf`; Lua, Markdown/MDX, Nix, then LSP fallback.
- [x] Linting: markdownlint-cli2 and statix on write/insert leave.
- [x] Treesitter: parser install/update plus highlighting/indent for shell, Git, JSON, Lua, Markdown, Nix, TOML, Vim, and YAML.
- [x] Picker/explorer: FFF find/grep on Unix; Snacks fallback on Windows; root/cwd files, grep, buffers, recent files, diagnostics, help, keymaps, and Snacks explorer.
- [x] Git: Gitsigns hunk navigation/stage/reset/preview/blame, Snacks status/diff, Lazygit.
- [x] Terminal/Pi: right-side 80-column Pi terminal, focus/toggle, file/position/selection send, Linux submit, Windows no-auto-submit.
- [x] Sessions: current/last restore and opt-out through persistence.nvim.
- [x] Editing extras with explicit prior opt-in: mini.surround, Yanky history/cycling, mini.ai, and hex-color highlights; native `<C-a>`/`<C-x>` handle integer increments.
- [x] UI: Catppuccin Macchiato, statusline, bufferline, which-key, Snacks notifications, and native command/message UI.
- [x] Markdown: in-editor render-markdown; browser preview remains intentionally disabled.
- [x] Platform behavior: Home Manager/Nix on Linux/macOS, writable lock and bootstrap on Windows, Unix-only hash-pinned FFF backend.
- [x] Provisioning/update: raw lock seeding, Windows plugin sync, FFF updater path, isolated lock refresh, CI integration.
- [x] Tests/health: raw headless config test, Pi terminal regression, Bash/PowerShell provisioning tests, Windows clean bootstrap integration. Existing doctor behavior remains unchanged; it checks managed links/tools but had no direct LazyVim health probe.

## Restored user-visible surface

Flash, Trouble, todo-comments, Treesitter textobject movement, session selector, Tailwind/hex highlights, broad buffer/LSP/Git/picker/Yanky mappings, LSP-first root detection, LazyVim editing options/autocmds, and mini.pairs safeguards are represented directly. Autotag, ts-comments, Noice, grug-far, Dial, dashboard, and duplicate picker aliases were later pruned. Pi behavior remains unchanged.

## Remaining gaps

- LazyVim framework commands and internals remain absent: `:LazyExtras`, changelog/news, framework health/default migration, and generated key groups.
- Neotest remains absent because baseline had zero adapters.
- Command-line and message UI use native Neovim; `<leader>snh` and `<leader>snl` expose native message history.
- Tailwind highlighting covers standard `*-500` utility colors instead of LazyVim's full 50-950 palette.
- Root detection uses attached LSP workspace/root, then common project markers, then cwd; it does not reproduce LazyVim's cache and every detector override.
- LazyVim-only automatic toggles, profiler controls, changelog, and niche GitHub picker mappings remain omitted.

## Recommendation

**Reject replacing LazyVim for now.** Near-parity raw config saves 5 enabled plugins, 11.3 MB, and 15.4% clean-start median, but warm-start median improves only 2.4% while owned Lua grows 182.8% and total config 249.6%. Runtime gain no longer offsets maintenance ownership. Keep branch as reviewable prototype unless framework independence is primary goal.
