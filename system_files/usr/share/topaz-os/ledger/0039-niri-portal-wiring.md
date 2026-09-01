---
title: niri session portals — ScreenCast wired up, Screenshot and Settings from COSMIC
date: 2026-08-25
status: active
paths:
  - /etc/niri/cosmic-shell.kdl
  - /usr/share/xdg-desktop-portal/niri-portals.conf
---
# niri session portals — ScreenCast wired up, Screenshot and Settings from COSMIC

Portal wiring for the COSMIC-on-niri session (ledger 0035): two gaps
that are consequences of niri not being started as `niri --session`, and
one routing trap in the packaged defaults.

**FileChooser (and friends).** xdg-desktop-portal routes an interface to
the first backend whose `.portal` file *declares* it — it never probes
what the backend actually *exports*. portal-gnome declares fourteen
interfaces but exports only Settings when not running on GNOME, so
upstream's `default=gnome;gtk;` sends FileChooser — and every other
interface both files declare — into "no such interface" with no
fallback; whether file dialogs worked at all depended on backend start
order. The packaged `niri-portals.conf` is patched to `default=gtk;gnome;`:
portal-gtk exports what it declares.

**ScreenCast.** niri implements the `org.gnome.Mutter.ScreenCast` D-Bus
API, which xdg-desktop-portal-gnome's ScreenCast backend uses — that is
the entire screen-sharing path on niri; there is no niri portal of its
own. But niri only registers its D-Bus interfaces when it is the session
leader, and in this session cosmic-session starts the compositor, so
screen sharing had no backend at all. The baked `/etc/niri/config.kdl`
sets niri's upstream escape hatch for exactly this arrangement,
`debug { dbus-interfaces-in-non-session-instances }`, and
`niri-portals.conf` routes ScreenCast to gnome explicitly (gtk never
implements it, but the load-bearing route should not be an accident of
list order). Known limit: the flag also claims the Mutter ScreenCast, Screenshot
and Introspect bus names, which would collide if a second compositor
session ever shared the user bus.

**Settings.** portal-gnome's Settings backend reads gsettings, but the
session's theme lives in cosmic-config, so flatpaks would not see a
COSMIC dark/light toggle. `configure.sh` appends an explicit preference
to the packaged `niri-portals.conf` routing Settings to portal-cosmic,
which reads cosmic-config directly and runs fine under niri (verified:
its Settings interface answers over D-Bus in a live niri session).
portal-gnome remains the fallback.

**FileChooser.** Routed to portal-cosmic as well: its dialog is COSMIC
Files in dialog mode — an ordinary window that works under niri and
matches the shell — with gtk as fallback.

**Screenshot.** Routed to portal-cosmic too, with gnome as fallback.
Its Screenshot and ScreenCast backends capture through
`ext-image-copy-capture-v1`, which upstream niri does not implement;
the topaz niri build does (ledger 0037), and a screenshot through this
route was verified end to end in the VM harness. ScreenCast stays on
gnome for now: the build's dmabuf capture path is disabled until it is
verified on real hardware, and the Mutter route already works.

Portal dialogs are transient windows from
another process that niri cannot tie to their parent and would tile;
the baked niri config floats them by app-id (the cosmic dialogs and
everything portal-gtk serves).

`topaz check` asserts the debug flag is in the baked config (whose
validity the ledger 0037 check proves against the baked binary), the
gtk-first default and the explicit preferences are in
`niri-portals.conf`, and the routing targets declare the interfaces they
are handed. Runtime verification is post-boot: file dialogs opening, a
screen-share picker appearing in the session, and a COSMIC theme toggle
reaching a flatpak.
