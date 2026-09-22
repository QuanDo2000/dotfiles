# Headless GUI User-Unit Failures

Use when `systemctl --user --failed` shows a desktop/portal/notification unit but no graphical session is expected.

## Evidence sequence

```bash
systemctl --user --no-pager --full status UNIT
journalctl --user -u UNIT -b --no-pager -n 200
systemctl --user cat UNIT
systemctl --user show-environment | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE)='
loginctl list-sessions
systemctl --user status graphical-session.target
ps -eo pid,comm,args | grep -E '(Xorg|Xwayland|sway|Hyprland|gnome-shell|kwin_wayland)'
```

Correlate the first failure timestamp with the surrounding user journal:

```bash
journalctl --user -b --since 'TIME-15sec' --until 'TIME+30sec' --no-pager
```

Static D-Bus services can activate outside `graphical-session.target`. A headless browser or CLI can request a portal/notification backend from an SSH-only user manager. Errors such as `cannot open display` then mean the activation context lacks a display; they do not by themselves prove a broken package.

## Decision

- **Real graphical session exists:** verify the compositor/login path imported `DISPLAY`, `WAYLAND_DISPLAY`, and `XDG_CURRENT_DESKTOP` into the user manager; fix that declarative session startup path.
- **No graphical session exists:** treat a no-display backend exit as an expected, usually harmless activation mismatch. Clear stale health state with `systemctl --user reset-failed UNIT` and verify `systemctl --user --failed` is empty.
- Do **not** mask a portal/backend merely to silence headless health checks if the same account may later start a real desktop session.
- Do not reinstall packages until status, journal, unit, environment, session target, and activation caller show an actual package/runtime defect.

## Recurrent graphical-session units under a lingering user manager

A lingering user manager can retain `graphical-session.target` as active after the compositor exits. Home Manager activation may then start changed units that are `WantedBy`/`PartOf` that target even though the manager has no `WAYLAND_DISPLAY`. Typical failures are clipboard daemons and PolicyKit agents reporting a missing Wayland/display connection.

For units that are valid only inside Wayland, gate the declarative unit at the real capability boundary instead of masking or disabling it:

```nix
systemd.user.services.example.Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
```

Before using this gate, verify the real compositor startup imports `WAYLAND_DISPLAY` into the user manager before starting `graphical-session.target`; otherwise a valid desktop launch will be skipped too. Add one repository regression assertion for the generated declaration, build and apply the Home Manager generation, then inspect `systemctl --user cat UNIT` for `ConditionEnvironment=WAYLAND_DISPLAY`.

Activation does not necessarily erase an earlier failed result when the new condition skips startup. After deployment, clear the stale result with `systemctl --user reset-failed UNIT`, then verify the unit is `inactive/dead`, `Result=success`, and `systemctl --user --failed` is empty. Keep unrelated static D-Bus portal failures on the separate diagnosis path below; do not add a Wayland condition to a backend that may be legitimately activated another way.

## Recurrent watchdog noise

If a verified headless-only activation recurs and a health watchdog intentionally reports every failed user unit, exclude only the exact benign unit in the watchdog—not in systemd. Preserve the `systemctl --user --failed` query result and every other failed unit:

```bash
if failed="$(systemctl --user --failed --no-legend --plain --no-pager 2>/dev/null)"; then
  failed="$(grep -Ev '^xdg-desktop-portal-gtk\.service([[:space:]]|$)' <<< "$failed")"
  [[ -z "$failed" ]] || alert "Failed user units: $(awk '{print $1}' <<< "$failed" | paste -sd, -)"
else
  alert "Unable to query failed user units."
fi
```

Keep the filter next to the user-unit query and add one self-test containing both the ignored unit and a synthetic real failure. Run shell syntax, the self-test, and a live watchdog invocation; the live run should be silent when this is the only failed unit. This avoids masking a portal backend that a future graphical session may need while keeping all unrelated failures actionable.

## Verification

```bash
systemctl --user --failed --no-pager --full
systemctl --user show UNIT -p ActiveState -p SubState -p Result
```

Expected after clearing a harmless headless failure: `inactive/dead`, `Result=success`, and zero failed user units. If the failure immediately returns, capture the activating process from the timestamp-correlated journal and fix or configure that caller rather than masking the backend.
