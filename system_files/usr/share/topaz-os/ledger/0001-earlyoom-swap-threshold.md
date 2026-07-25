---
title: earlyoom enabled with a swap-usage threshold
date: 2026-07-25
status: active
paths:
  - /etc/default/earlyoom
  - /usr/lib/systemd/system/earlyoom.service
---
# earlyoom enabled with a swap-usage threshold

The kernel OOM killer reacts too late for desktop use, and systemd-oomd proved
too conservative: with a large browser workload the system would swap-thrash
into unresponsiveness before either intervened.

earlyoom is installed and enabled by default. The configuration follows the
Fedora Workstation defaults (https://pagure.io/fedora-workstation/issue/119)
with one addition: `-s 50` also triggers intervention when swap is more than
half full, which catches thrash spirals while the desktop is still responsive.
Browser content processes are preferred as victims; session-critical processes
(compositors, display managers, and cosmic-comp/cosmic-session for the COSMIC
session) are avoided.
