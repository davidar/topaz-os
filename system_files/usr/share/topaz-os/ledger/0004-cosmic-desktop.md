---
title: COSMIC desktop installed alongside GNOME
date: 2026-07-25
status: superseded
paths:
  - /usr/share/wayland-sessions/cosmic.desktop
  - /usr/bin/cosmic-session
---
# COSMIC desktop installed alongside GNOME

COSMIC (1.4.x, from the Fedora repositories) is installed in addition to the
base image's GNOME, selectable per-login from the display manager's
session list. GDM remained the display manager until ledger 0045 (greetd
with tuigreet), so that the GNOME session stayed fully supported as a
fallback and the base image's login integration (fingerprint auth,
session handling) was untouched; the GNOME session is still listed. The
`cosmic-greeter` package is present — it is a hard dependency of
`cosmic-session` — but its service is not enabled.

Rationale: evaluating COSMIC as a daily-driver desktop without committing to
it. If the evaluation concludes, this entry should be updated — either the
GNOME session becomes the vestigial one or the COSMIC set gets removed.

**Superseded 2026-10-25 (ledger 0047).** The evaluation concluded the
other way: the daily session is niri (topaz) (ledger 0041), and the
COSMIC session and shell are removed from the image. The COSMIC
applications stay as ordinary packages; GNOME remains the fallback
session.
