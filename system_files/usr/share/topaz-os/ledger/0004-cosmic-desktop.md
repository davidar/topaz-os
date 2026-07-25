---
title: COSMIC desktop installed alongside GNOME
date: 2026-07-25
status: active
paths:
  - /usr/share/wayland-sessions/cosmic.desktop
  - /usr/bin/cosmic-session
  - /etc/systemd/system/display-manager.service
---
# COSMIC desktop installed alongside GNOME

COSMIC (1.4.x, from the Fedora repositories) is installed in addition to the
base image's GNOME, selectable per-login from the GDM session picker.
GDM remains the display manager so the GNOME session stays fully supported
as a fallback and the base image's login integration (fingerprint auth,
session handling) is untouched. The `cosmic-greeter` package is present —
it is a hard dependency of `cosmic-session` — but its service is not
enabled; `topaz check` verifies that `display-manager.service` still
resolves to GDM.

Rationale: evaluating COSMIC as a daily-driver desktop without committing to
it. If the evaluation concludes, this entry should be updated — either the
GNOME session becomes the vestigial one or the COSMIC set gets removed.
