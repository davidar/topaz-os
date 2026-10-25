---
title: The wallpaper follows the base image's choice and schedule
date: 2026-10-25
status: active
paths:
  - /usr/lib/systemd/user/topaz-background.service
  - /usr/libexec/topaz/background
  - /usr/share/topaz-os/session.conf
---
# The wallpaper follows the base image's choice and schedule

Bluefin's GNOME wallpaper looks dynamic but is mostly a build-time
choice: `/usr/share/glib-2.0/schemas/zz0-bluefin-modifications.gschema.override`
pins one of the month-named timed wallpapers under
`/usr/share/backgrounds/bluefin/` (`picture-uri-dark`), and GNOME reads
that XML — a day image, a night image, a start time and two cross-fades
— on its clock. A new month's artwork arrives with the next base image,
not at runtime.

The niri (topaz) session (ledger 0041) paints with swaybg, which takes
one image and knows nothing about schedules. Until now the image unit
painted a fixed file and the per-user choice lived in a topaz-home
recipe that rewrote a drop-in and restarted the unit from a timer —
state and machinery for something GNOME gets from the base for free.

`topaz-background.service` now runs `/usr/libexec/topaz/background`,
which reads the same override, walks the same XML (each transition
counted as its midpoint: the old image for the first half, the new for
the second), runs swaybg with the image the schedule names now, and
restarts it at the next change. The visible difference from GNOME is
the cross-fade: swaybg cannot blend, so the switch is a cut, twice a
day. No wallpaper daemon that could swap images in place is packaged in
Fedora 44 (swww, wpaperd, awww are absent); the cut is the honest
option.

One knob, in the session's knob file (ledger 0046): `TOPAZ_WALLPAPER`
names an image, or another timed XML, in place of the base image's
choice. Unset is the default, and the default needs no per-user file.
The unit's drop-in override still works for anything else.

Check: the script and unit are wired, the knob is documented, the
override names an existing XML under the Bluefin artwork directory, and
the script's `--print` at noon and at 22:00 of the build day resolves to
a day and a night image that exist; a knob naming a plain image is
printed back unchanged. Post-boot: the wallpaper after login matches
GNOME's for the hour, and changes at the schedule's times.
