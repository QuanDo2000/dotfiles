# Inspecting and Steering Existing Pi tmux Agents

Use when user asks for progress or wants to send instructions to a Pi agent already running in tmux.

## Procedure

1. Discover tmux and Pi processes with `pgrep -a tmux` and `pgrep -af 'pi($| )|pi-coding-agent|node.*pi'`.
2. If ordinary `tmux list-sessions` cannot find socket, inspect tmux server or Pi `/proc/<pid>/environ` for `TMUX_TMPDIR` and `TMUX`. Reuse that runtime directory; do not assume `/tmp/tmux-$UID`.
3. List sessions and panes using the recovered environment:
   ```bash
   TMUX_TMPDIR=<runtime-dir> tmux list-sessions
   TMUX_TMPDIR=<runtime-dir> tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} pid=#{pane_pid} cmd=#{pane_current_command} path=#{pane_current_path}'
   ```
4. Capture enough scrollback to find latest completed action, current spinner/prompt, test results, blockers, and final report:
   ```bash
   TMUX_TMPDIR=<runtime-dir> tmux capture-pane -p -J -S -200 -t <session:window.pane>
   ```
5. Corroborate claims before reporting side effects: use live Git/process state when available. Distinguish parent Pi process from subagent children via process tree and `PI_SUBAGENT_*` environment variables.
6. To steer an idle or active parent, send one complete instruction and Enter:
   ```bash
   TMUX_TMPDIR=<runtime-dir> tmux send-keys -t <target> '<instruction>' Enter
   ```
7. Recapture after sending to verify delivery. Never repeat a delivered command unless fresh state shows it did not land.

## Reporting

State one of: working, blocked/waiting, finished-uncommitted, or finished-pushed. Include shortest decisive evidence: current task, last checks, commit/push state, and any unrelated files deliberately excluded.

## Pitfalls

- Default tmux socket lookup can fail while server is healthy because `TMUX_TMPDIR` differs.
- A running `pi` child may be a reviewer/subagent, not user-facing tmux parent.
- Pane text is evidence of what agent said, not proof of current Git or external state; verify side effects separately.
- Do not steal focus or attach interactively when `capture-pane` and `send-keys` suffice.
