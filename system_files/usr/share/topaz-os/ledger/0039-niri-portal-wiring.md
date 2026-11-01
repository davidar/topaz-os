---
title: niri session portals — dialogs from gtk; ScreenCast, Screenshot and Settings on gnome
date: 2026-08-25
status: active
paths:
  - /etc/niri/config.kdl
  - /usr/share/xdg-desktop-portal/niri-portals.conf
---
# niri session portals — dialogs from gtk; ScreenCast, Screenshot and Settings on gnome

Portal wiring, written for the COSMIC-on-niri session (ledger 0035) and
inherited by the niri (topaz) session (ledger 0041): two gaps that were
consequences of niri not being started as `niri --session`, and one
routing trap in the packaged defaults. Since ledger 0047 removed the
COSMIC-on-niri session, `niri --session` performs the environment
import and the D-Bus registration itself; what remains of this entry is
the portal routing in `niri-portals.conf` and the portal-dialog float
rule, now in the baked `/etc/niri/config.kdl`. Since 2026-10-31 the
routing names only the two backends the base image ships, portal-gtk
and portal-gnome: xdg-desktop-portal-cosmic, the last COSMIC process the
session ran, is gone, and cosmic-screenshot, its one client, with it.

**FileChooser (and friends).** xdg-desktop-portal routes an interface to
the first backend whose `.portal` file *declares* it — it never probes
what the backend actually *exports*. portal-gnome declares eighteen
interfaces but exports only the few it can serve when not running on
GNOME, so upstream's `default=gnome;gtk;` sends FileChooser — and every
other interface both files declare — into "no such interface" with no
fallback; whether file dialogs worked at all depended on backend start
order. The packaged `niri-portals.conf` is patched to `default=gtk;gnome;`,
and FileChooser is named explicitly for gtk: portal-gtk exports what it
declares, and its file dialog is GTK's own.

**ScreenCast.** niri implements the `org.gnome.Mutter.ScreenCast` D-Bus
API, which xdg-desktop-portal-gnome's ScreenCast backend uses — that is
the entire screen-sharing path on niri; there is no niri portal of its
own. niri registers its D-Bus interfaces only when it is the session
leader; in the COSMIC-on-niri session cosmic-session started the
compositor, so screen sharing had no backend until the baked config set
niri's escape hatch, `debug { dbus-interfaces-in-non-session-instances }`.
`niri --session` is the leader now (ledger 0041) and the flag is gone
with that session (ledger 0047). `niri-portals.conf` routes ScreenCast
to gnome explicitly (gtk never implements it, but the load-bearing route
should not be an accident of list order).

**Settings.** Routed to portal-gnome, whose backend answers
`color-scheme` and `accent-color` from gsettings
(`org.gnome.desktop.interface`). Until 2026-10-25 it went to
portal-cosmic, which read the theme from cosmic-config so that a COSMIC
dark/light toggle reached flatpaks; with no COSMIC shell left to write
cosmic-config (ledger 0047), gsettings is the one theme switch the
session has, and the GNOME session reads the same keys.

**Screenshot.** Routed to portal-gnome, whose backend drives the
`org.gnome.Shell.Screenshot` D-Bus API; `niri --session` registers that
name and implements its `Screenshot` and `PickColor` methods. From
2026-08-25 to 2026-10-31 it went to portal-cosmic, which captured through
`ext-image-copy-capture-v1` (the topaz niri build implements it, ledger
0037) and whose file dialog, COSMIC Files in dialog mode, also served
FileChooser; both routes now run through the base image's own backends.

Portal dialogs are transient windows from
another process that niri cannot tie to their parent and would tile;
the baked niri config floats them by app-id (everything portal-gtk
serves).

`topaz check` asserts the gtk-first default and the explicit preferences
are in `niri-portals.conf`, the routing targets declare the interfaces
they are handed, the baked config (whose validity the ledger 0037 check
proves against the baked binary) floats portal-gtk's dialogs, and no
COSMIC portal backend or dialog rule remains.
Runtime verification is post-boot: file dialogs opening, a screen-share
picker appearing in the session, a portal screenshot landing, and the
gsettings colour scheme reaching a flatpak.
