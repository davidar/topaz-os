---
title: cosmic-comp built from the topaz fork
date: 2026-07-27
status: active
paths:
  - /usr/bin/cosmic-comp
  - /usr/share/topaz-os/cosmic-comp-fork
---
# cosmic-comp built from the topaz fork

The compositor binary is not Fedora's: it is compiled in the image build
(Containerfile `comp-build` stage) from a pinned commit of
<https://github.com/davidar/cosmic-comp>, branch `topaz`, which carries
four small patch series on top of the packaged 1.6.0:

- **Config-driven workspace swipe gestures.** Upstream hardcodes
  four-finger workspace switching and silently swallows three-finger
  swipes (captured but never forwarded to applications). The fork makes
  the finger counts, the swipe physics (distance, commit thresholds,
  velocity window, settle spring), and a rubber-band bounce at the ends
  of the workspace strip all configuration — hot-reloadable through
  cosmic-config (`com.system76.CosmicComp` `gestures` key), defaults
  matching upstream behavior. Pending upstream as the answer to
  pop-os/cosmic-epoch#54; drop the corresponding patches when merged.
- **smithay fixes** (via the fork's pinned github.com/davidar/smithay):
  probe DRM master with AUTH_MAGIC instead of trusting `drmSetMaster`
  errno (needed for sessions launched from a bare VT during compositor
  development), and accept zero-size positioner anchor rectangles, which
  the stable xdg-shell spec allows but smithay fatally rejected.
- **Startup retry for busy DRM devices** (cherry-pick of upstream
  pop-os/cosmic-comp#2670): taking a device fails with EBUSY while the
  compositor being replaced is still shutting down, and coming up with
  no device is fatal. Drop when upstream merges it.
- **Trace-level logging available in release builds** for live debugging.

Provenance: `/usr/share/topaz-os/cosmic-comp-fork` records the repo, the
exact commit, and the Fedora base version the fork tracks. The build
fails loudly if Fedora ships a cosmic-comp other than that base version,
so a distro bump forces a fork rebase instead of silently shadowing newer
code. `topaz check` asserts the binary really deviates from the packaged
one (rpm verification) and that the version pin still holds.

The `comp-build` stage's Fedora release is pinned to the base image's:
building on a newer release links against a newer glibc than the image
ships and the binary fails to load at session start (learned the hard way
when a builder bump to Fedora 45 black-screened every COSMIC login).
`topaz check` asserts all of the binary's libraries resolve, so a
mismatched builder fails the build instead of the login.

The fork was daily-driven and VT-tested through the `topaz dev` overlay
workflow (ledger 0014) before graduating into the image — that is the
intended pipeline for any future fork work.
