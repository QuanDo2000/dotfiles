# Global Agent Instructions

## Default Agent Modes

Ponytail and Caveman are active at `full` at every main-agent and subagent startup. Load their installed skill instructions before the first response; Ponytail governs implementation choices and Caveman governs terse output. Keep both active until the user explicitly disables or changes them.

## Code Search

Use codebase-memory first: index once, then prefer `get_architecture`, `search_graph`, `trace_path`, and `get_code_snippet`; run `detect_changes` before finalizing code edits. Use FFF (`find_files`/`grep`/`multi_grep`, or Pi's `fffind`/`ffgrep`/`fff-multi-grep`) for raw filename/text lookup and fallback instead of shell grep, glob, or find.
