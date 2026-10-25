---
title: niri (topaz) session — no COSMIC shell
date: 2026-10-17
status: active
paths:
  - /usr/share/wayland-sessions/topaz.desktop
  - /usr/lib/systemd/user/caustics-bar.service
  - /usr/lib/systemd/user/topaz-locker.service
  - /usr/lib/systemd/user/topaz-idle.service
  - /usr/lib/systemd/user/topaz-polkit-agent.service
  - /usr/lib/systemd/user/topaz-background.service
  - /usr/lib/systemd/user/topaz-clipboard.service
  - /usr/libexec/topaz/locker
  - /etc/swaylock/config
  - /etc/pam.d/swaylock
  - /usr/lib/systemd/user-preset/45-topaz.preset
  - /usr/bin/topaz-osd
  - /etc/niri/config.kdl
---
# niri (topaz) session — no COSMIC shell

A third session entry, "niri (topaz)", runs niri's own systemd session
(`niri-session`: environment import, `graphical-session.target`,
`niri-shutdown.target` on exit) with the caustics bar (ledger 0044) as
its panel and standalone, toolkit-free tools for everything
cosmic-session used to supervise. No COSMIC shell process runs in it.
GNOME remains as the fallback session (the COSMIC sessions, ledgers
0004 and 0035, were removed with the forks they needed — ledger 0047).

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
on `ConditionEnvironment=XDG_SESSION_DESKTOP=topaz` (the entry's
`DesktopNames`, as cosmic-greeter sets it; a single name, because the
greeter passes the value through greetd's shell, where a `;`-separated
list ends the session command) so the GNOME session is untouched:

| Role | Was | Now |
|---|---|---|
| session supervision | cosmic-session + startup shim | `niri --session` (niri.service) |
| bar, dock, tray, charts, clock | cosmic-panel + applets | caustics-bar (`caustics-bar.service`, ledger 0044) |
| notifications | cosmic-notifications + panel applet | the bar's own daemon (its `caustics-notify` sidecar) |
| workspaces overview | shim | the bar's overview button, through niri's IPC |
| locker | cosmic-greeter, resident, restarted by cosmic-session | swaylock, `topaz-locker.service`: swayidle starts it on logind's Lock signal and before sleep; it exits on unlock, so the unit is active exactly while locked (Restart=on-failure for a locker that dies while locked). The unit is `Type=notify` through `/usr/libexec/topaz/locker`, which forwards swaylock's lock-held notification (`--ready-fd`), so swayidle's before-sleep holds the suspend until the screen is locked. Password only — its PAM stack is `password-auth`, without the 5 s fingerprint wait `login` carries |
| idle → fade → lock → blank → suspend | cosmic-idle (fork) | swayidle, `topaz-idle.service`; chayang fades the screen before the lock, and the timeouts are knobs in `~/.config/topaz/session.conf` (ledger 0046) |
| on-screen display | cosmic-osd | the bar's own toasts: its audio and power sidecars watch PipeWire and the backlight; `topaz-osd` applies the key presses (brightness through logind's `SetBrightness`, no brightnessctl, no udev rule) |
| polkit agent | cosmic-osd | cosmic-osd, `topaz-polkit-agent.service` (its OSD half idles without cosmic-settings-daemon; it panics once the compositor is gone at logout, after the session is over) |
| launcher / app library | cosmic-launcher, cosmic-app-library | fuzzel (Mod+D) |
| wallpaper | cosmic-bg | swaybg, `topaz-background.service`: the base image's timed wallpaper on its own day/night schedule, `TOPAZ_WALLPAPER` in the knob file for another (ledger 0048) |
| dark/light for portals | portal-cosmic Settings (reads cosmic-config) | portal-gnome Settings, from gsettings `color-scheme` (ledger 0039) |
| clipboard history | — | cliphist, `topaz-clipboard.service` |

The baked niri config serves all sessions: its startup shim spawn goes
through `/usr/libexec/topaz/cosmic-shim`, which exits at once when
`COSMIC_SESSION_SOCK` is absent; Mod+D spawns fuzzel and the media keys
`topaz-osd` in every session (both work under cosmic-session too).
Portals: `niri --session` resets `XDG_CURRENT_DESKTOP` to `niri`, so the
session shares the COSMIC-on-niri routing (ledger 0039) unchanged.

A lock screen that exists only while locked has no state to wedge: the
failure modes ledger 0034 patches in the resident COSMIC locker (an
abandoned lock leaving it deaf, a session lookup that fails under a
service manager) do not arise. The cost is fingerprint unlock, which
swaylock does not offer.

Still COSMIC in this session, deliberately and for now: cosmic-osd as
the polkit agent (no toolkit-free agent exists) and the COSMIC file
dialog and screenshot portals (ledger 0039). The login screen left too:
greetd runs tuigreet on the console (ledger 0045). Every other piece is
toolkit-free: no GTK or Qt joins the session. The COSMIC packages the session no longer needs stay installed
while the fallback sessions exist; their removal follows once this
session has been lived in.

Check: the session entry, every unit (present, gated, enabled; the
locker present, started by swayidle and not enabled), swaylock's config
and PAM stack, the shim, the packages (and that mako is gone), the
portal routing and the baked binds. Post-boot: the VM harness boots the session with
`TOPAZ_TEST_SESSION=topaz-niri` and asserts the bar runs from its
installed set and owns the notification name, locks and unlocks it at
the console (the lock-unlock suite), and logs out and back in through
the greeter (relogin-cycle); suspend, the OSD and the polkit prompt are
hardware checks.
