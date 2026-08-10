---
title: Userland moved to the topaz-home companion repo
date: 2026-08-10
status: active
paths:
  - /usr/share/ublue-os/just/60-custom.just
---
# Userland moved to the topaz-home companion repo

The image used to bake a layer of pure userland: the night-shift triage
timer (formerly entry 0005), the opt-in user-setup recipes and their helper
units and scripts (0016), and the Qt dark-theme recipe (0011). None of it
touched the boot path, yet changing a text file meant an image build and a
reboot.

That layer now lives in its own repo,
[topaz-home](https://github.com/davidar/topaz-home), and installs per user
into `~/.local` and `~/.config/systemd/user`. The boundary is blast radius:
the image carries what needs atomic updates, signatures, and rollback — the
boot path, the compositor, the package set. Everything above that updates at
git speed, is enabled deliberately per user, and is fixable from a terminal
without a reboot.

The image's only reference to the companion is the `ujust topaz-home`
recipe in the path above: it clones the repo and prints next steps, and
never applies anything — the image still runs nothing from it
automatically. The `topaz` CLI keeps only its image-coupled verbs (`why`,
`ledger`, `check`, `dev`); night-shift management and report reading are
companion verbs.
