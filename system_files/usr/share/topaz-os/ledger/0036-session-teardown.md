---
title: Session launchers tear graphical-session.target down on exit
date: 2026-08-22
status: active
paths:
  - /usr/bin/start-cosmic
  - /usr/bin/start-cosmic-niri
  - /usr/lib/systemd/user/topaz-session-shutdown.target
---
# Session launchers tear graphical-session.target down on exit

`graphical-session.target` is the user-manager target that session-scoped
services — the xdg-desktop-portal daemon and its backends, autostart
entries, Flatpak app scopes — hang off with `PartOf=`, so that they stop
when the graphical session ends. The packaged `start-cosmic` never makes
that happen: it `exec`s cosmic-session, and cosmic-session stops only its
own `cosmic-session.target` on logout. The target is meant to fall away on
its own (`StopWhenUnneeded=`), but `xdg-desktop-portal.service` declares
`Requisite=graphical-session.target`, which pins it. Net effect: after a
logout the portal daemon and everything else under the target survive
with the dead session's environment, and the next login of either session
inherits a portal wired to the previous compositor — switching COSMIC →
"COSMIC on niri" without a reboot gave a portal backend that took most of
a minute to come up on niri, during which every app that queries the
Settings portal at startup (terminals, GTK and Electron apps) sat blocked
on the D-Bus timeout.

The fix is the teardown niri-session and gnome-session already perform.
Both launchers (`start-cosmic`, and `start-cosmic-niri` derived from it —
ledger 0035) are patched at build time to run cosmic-session as a child
and, once it exits, start `topaz-session-shutdown.target`, whose
`Conflicts=graphical-session.target graphical-session-pre.target` forces
both down, then unset the session variables (`WAYLAND_DISPLAY`, `DISPLAY`,
`NIRI_SOCKET`, `XDG_SESSION_TYPE`, `XDG_CURRENT_DESKTOP`,
`XDG_SESSION_DESKTOP`) from the user manager so nothing activated between
sessions sees stale values. The launcher exits with cosmic-session's
status. The patch is grep-guarded: the build fails if the packaged
script's exec lines move or change shape. Upstream candidate for
cosmic-session / start-cosmic.
