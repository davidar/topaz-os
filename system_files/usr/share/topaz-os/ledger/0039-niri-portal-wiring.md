---
title: niri session portals — ScreenCast and Settings on gnome, FileChooser and Screenshot from COSMIC
date: 2026-08-25
status: active
paths:
  - /etc/niri/config.kdl
  - /usr/share/xdg-desktop-portal/niri-portals.conf
---
# niri session portals — ScreenCast and Settings on gnome, FileChooser and Screenshot from COSMIC

Portal wiring, written for the COSMIC-on-niri session (ledger 0035) and
inherited by the niri (topaz) session (ledger 0041): two gaps that were
consequences of niri not being started as `niri --session`, and one
routing trap in the packaged defaults. Since ledger 0047 removed the
COSMIC-on-niri session, `niri --session` performs the environment
import and the D-Bus registration itself; what remains of this entry is
the portal routing in `niri-portals.conf` and the portal-dialog float
rule, now in the baked `/etc/niri/config.kdl`.

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

**Settings.** Routed to portal-gnome, whose backend answers
`color-scheme` and `accent-color` from gsettings
(`org.gnome.desktop.interface`). Until 2026-10-25 it went to
portal-cosmic, which read the theme from cosmic-config so that a COSMIC
dark/light toggle reached flatpaks; with no COSMIC shell left to write
cosmic-config (ledger 0047), gsettings is the one theme switch the
session has, and the GNOME session reads the same keys.

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
