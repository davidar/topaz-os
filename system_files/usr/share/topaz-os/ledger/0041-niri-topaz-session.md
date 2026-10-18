---
title: niri (topaz) session — no COSMIC shell
date: 2026-10-17
status: active
paths:
  - /usr/share/wayland-sessions/topaz-niri.desktop
  - /usr/lib/systemd/user/caustics-bar.service
  - /usr/lib/systemd/user/topaz-locker.service
  - /usr/lib/systemd/user/topaz-idle.service
  - /usr/lib/systemd/user/topaz-osd.socket
  - /usr/lib/systemd/user/topaz-osd.service
  - /usr/lib/systemd/user/topaz-polkit-agent.service
  - /usr/lib/systemd/user/topaz-background.service
  - /usr/lib/systemd/user/topaz-clipboard.service
  - /usr/lib/systemd/user-preset/45-topaz.preset
  - /usr/libexec/topaz/cosmic-shim
  - /usr/bin/topaz-osd
  - /etc/xdg/wob/wob.ini
  - /etc/niri/config.kdl
  - /etc/niri/cosmic-shell.kdl
---
# niri (topaz) session — no COSMIC shell

A third session entry, "niri (topaz)", runs niri's own systemd session
(`niri-session`: environment import, `graphical-session.target`,
`niri-shutdown.target` on exit) with the caustics bar (ledger 0044) as
its panel and standalone, toolkit-free tools for everything
cosmic-session used to supervise. No COSMIC shell process runs in it.
The COSMIC-on-niri session (ledger 0035) and the stock COSMIC session
remain unchanged as fallbacks.

Why: the COSMIC shell pieces the niri session ran — session supervision,
panel and applets, notifications, on-screen display, polkit agent,
launcher, app library, wallpaper, theme propagation, idle handling — had
accumulated forks, handshake seams and incidents (ledgers 0036, 0038,
0039, the startup shim) for no functional gain over tools every other
niri setup uses, and every fix meant another fork of a toolkit this
image is leaving. The bar, the one piece that did something no packaged
tool does (dock with window previews, charts, tray), now has a
toolkit-free replacement of its own.

What runs, as user units wanted by `graphical-session.target` and gated
on `ConditionEnvironment=XDG_SESSION_DESKTOP=topaz` (the first of the
entry's `DesktopNames`, as cosmic-greeter sets it) so the COSMIC
sessions are untouched:

| Role | Was | Now |
|---|---|---|
| session supervision | cosmic-session + startup shim | `niri --session` (niri.service) |
| bar, dock, tray, charts, clock | cosmic-panel + applets | caustics-bar (`caustics-bar.service`, ledger 0044) |
| notifications | cosmic-notifications + panel applet | the bar's own daemon (its `caustics-notify` sidecar) |
| workspaces overview | shim | the bar's overview button, through niri's IPC |
| locker | cosmic-greeter, restarted by cosmic-session | cosmic-greeter, `topaz-locker.service` (Restart=on-failure, ledger 0034) |
| idle → lock → blank → suspend | cosmic-idle (fork) | swayidle, `topaz-idle.service` (drop-in to retune) |
| on-screen display | cosmic-osd | wob via `topaz-osd.socket`, fed by `topaz-osd` from the volume/brightness binds (brightness through logind's `SetBrightness`; no brightnessctl, no udev rule) |
| polkit agent | cosmic-osd | cosmic-osd, `topaz-polkit-agent.service` (its OSD half idles without cosmic-settings-daemon) |
| launcher / app library | cosmic-launcher, cosmic-app-library | fuzzel (Mod+D) |
| wallpaper | cosmic-bg | swaybg, `topaz-background.service` (base artwork; a per-user override replaces it) |
| dark/light for portals | portal-cosmic Settings (reads cosmic-config) | unchanged |
| clipboard history | — | cliphist, `topaz-clipboard.service` |

The baked niri config serves all sessions: its startup shim spawn goes
through `/usr/libexec/topaz/cosmic-shim`, which exits at once when
`COSMIC_SESSION_SOCK` is absent; Mod+D spawns fuzzel and the media keys
`topaz-osd` in every session (both work under cosmic-session too).
Portals: `niri --session` resets `XDG_CURRENT_DESKTOP` to `niri`, so the
session shares the COSMIC-on-niri routing (ledger 0039) unchanged.

Still COSMIC in this session, deliberately and for now: the greeter as
display manager and locker (ledger 0034; its login screen still runs on
cosmic-comp), cosmic-osd as the polkit agent (no toolkit-free agent
exists), and the COSMIC file dialog and screenshot portals (ledger
0039). Every other piece is toolkit-free: no GTK or Qt joins the
session. The COSMIC packages the session no longer needs stay installed
while the fallback sessions exist; their removal follows once this
session has been lived in.

Check: the session entry, every unit (present, gated, enabled), the
shim, the packages (and that mako is gone), the portal routing and the
baked binds. Post-boot: the VM harness boots the session with
`TOPAZ_TEST_SESSION=topaz-niri` and asserts the bar runs from its
installed set and owns the notification name; lock/unlock, suspend, the
OSD and the polkit prompt are hardware checks.
