# Client-specific tmux auto-attach opt-out

Use this when a shared zsh configuration auto-attaches tmux, but one SSH client (for example Termux) should receive a normal login shell.

## Pattern

Do not infer the client from `TERM`, `SSH_CLIENT`, or terminal dimensions: those are generic or unstable. Add one explicit environment guard to the existing shared auto-attach condition:

```zsh
if [[ -t 0 && -z "$TMUX" && -o interactive && -z "$ZSH_TMUX_STARTED" && -z "$NO_TMUX" \
      && "$TERM_PROGRAM" != "vscode" && -z "$INSIDE_EMACS" && -z "$VIMRUNTIME" ]] \
   && command -v tmux >/dev/null 2>&1; then
  # existing attach/create flow
fi
```

Give the exceptional client a separate SSH alias so SCP/SFTP and normal aliases remain unaffected:

```sshconfig
Host server-termux
    HostName server.example.invalid
    User username
    RequestTTY force
    RemoteCommand exec env NO_TMUX=1 zsh -l
```

Connect with `ssh server-termux`.

## Verification

1. Add a regression assertion that the shared condition contains `-z "$NO_TMUX"`.
2. Run the repository's complete validation suite.
3. Activate the generated shell configuration.
4. Verify the exceptional alias opens outside tmux.
5. Verify an ordinary SSH login still follows the existing tmux attach/create behavior.
6. Inspect the Git diff and commit only the guard plus its regression coverage.

This pattern was originally exercised with Termux; verify it against the current client and shell. Avoid SSH daemon changes (`AcceptEnv`, key-specific forced commands, or source-IP matching) unless an explicit client alias cannot meet the requirement.