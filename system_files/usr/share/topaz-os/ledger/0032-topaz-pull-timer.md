---
title: Updates staged daily by topaz pull, ahead of uupd
date: 2026-08-15
status: active
paths:
  - /usr/lib/systemd/system/topaz-pull.service
  - /usr/lib/systemd/system/topaz-pull.timer
  - /usr/lib/systemd/system-preset/45-topaz.preset
---
# Updates staged daily by topaz pull, ahead of uupd

uupd's image step drives `bootc upgrade`, which fetches layers serially
through the image proxy and cannot do partial pulls — on this image's
~400 content-based layers that meant re-downloading gigabytes for
updates whose real delta is tens of megabytes (ledgers 0028, 0029,
0031).

`topaz-pull.timer` runs `topaz pull` daily at 03:30, half an hour
before uupd's 04:00 window: the update is fetched with parallel partial
pulls and staged, so uupd's bootc step finds the staged digest already
current and no-ops. uupd stays enabled and keeps its other duties
(flatpak, brew, distrobox); if the pull fails — no network, say — the
next uupd run still updates the machine the slow way. `topaz pull`
itself exits untouched when the registry digest is already staged or
booted, so the daily fire is idempotent.

Both timers are `Persistent`, so a boot after downtime can queue both
at once; the service orders itself `Before=uupd.service` for exactly
that collision. This unit retires when bootc learns parallel partial
pulls natively ([bootc#20](https://github.com/bootc-dev/bootc/issues/20)).
