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

The niri (topaz) session (ledger 0041) draws its wallpaper on the
caustics canvas (ledger 0049), which shows one picture at a time and
cross-fades to the next on command. Before it, the image unit ran swaybg
on a fixed file and the per-user choice lived in a topaz-home recipe
that rewrote a drop-in and restarted the unit from a timer — state and
machinery for something GNOME gets from the base for free.

`topaz-background.service` runs `/usr/libexec/topaz/background`, which
reads the same override, walks the same XML and drives the canvas
through `caustics-canvasctl`: a static entry is a cut to its image, a
transition a fade to its target over the XML's own duration, so the
session blends day into night over the same hours GNOME does. The unit
orders itself after the canvas's, and the script retries its first
request until the canvas's socket answers. swaybg stays installed as the
rescue: with `caustics-canvas.service` masked, a drop-in on this unit
puts it back.

One knob, in the session's knob file (ledger 0046): `TOPAZ_WALLPAPER`
names an image, or another timed XML, in place of the base image's
choice. Unset is the default, and the default needs no per-user file.
The unit's drop-in override still works for anything else.

Check: the script drives the canvas and not swaybg, the unit is ordered
after the canvas's, the knob is documented, the override names an
existing XML under the Bluefin artwork directory, the script's `--print`
at noon and at 22:00 of the build day resolves to a day and a night
image that exist, a knob naming a plain image is printed back unchanged,
and a probe schedule resolves a transition to its target with the
seconds of fade left. Post-boot: the canvas reports the schedule's image
after login, and the picture changes at the schedule's times.
