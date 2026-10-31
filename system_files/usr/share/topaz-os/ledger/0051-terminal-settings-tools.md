---
title: Terminal tools for the settings the shell does not cover
date: 2026-10-31
status: active
paths:
  - /usr/share/topaz-os/packages.lock
---
# Terminal tools for the settings the shell does not cover

The niri (topaz) session has no settings application of its own and no
toolkit: the caustics bar and canvas (ledgers 0044, 0049) cover the daily
cases — joining a network, pairing a device, volume, brightness, the
lock — and everything rarer is done in a terminal, which also means over
ssh. cosmic-settings, the last COSMIC piece the session relied on for
network and Bluetooth joining, leaves once the canvas's secret and
pairing agents have been lived in.

This entry adds one packaged terminal tool per remaining domain, chosen
from a survey of what Fedora 44 ships (the unpackaged candidates, mostly
Ratatui programs, are installed per user from topaz-home — ledger 0026 —
and are not image material):

| Domain | Tool |
|---|---|
| network connections, VPN, the full editor | NetworkManager-tui (`nmtui`) |
| audio devices, routing, volumes | wiremix |
| output modes and layout; hotplug profiles | wlr-randr; kanshi (`niri msg output` for the ad hoc change) |
| colour temperature | wlsunset |
| screenshots and recording | grim, slurp, wf-recorder (niri's own screenshot actions for the keyboard) |
| processes and resources | btop |
| disk usage; removable mounts | ncdu and gdu (the same browser; gdu scans in parallel); bashmount |

Nothing is enabled or configured: kanshi and wlsunset are daemons a user
starts (a topaz-home recipe is the intended place), the rest are commands.
No GTK or Qt joins the image for any of them. Backlight stays on logind's
`SetBrightness` through `topaz-osd` (ledger 0041); nothing here needs
brightnessctl or a udev rule.

Check: every tool's binary resolves on the image's PATH.
