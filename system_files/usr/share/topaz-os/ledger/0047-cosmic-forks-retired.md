---
title: COSMIC session, shell and forks removed; the apps stay
date: 2026-10-25
status: active
paths:
  - /usr/share/topaz-os/packages.lock
  - /etc/niri/config.kdl
  - /usr/bin/cosmic-osd
  - /usr/libexec/xdg-desktop-portal-cosmic
---
# COSMIC session, shell and forks removed; the apps stay

The image no longer carries a COSMIC session. cosmic-session and
everything only it needed — cosmic-comp, cosmic-greeter, cosmic-panel,
cosmic-launcher, cosmic-applets, cosmic-app-library, cosmic-settings,
cosmic-settings-daemon, cosmic-bg, cosmic-notifications, cosmic-idle,
cosmic-randr, cosmic-workspaces, cosmic-config-fedora, and the
cosmic-initial-setup and cosmic-wallpapers it dragged along (ledger
0025) — are out of the lock. The four of those the image used to build
from forks (cosmic-comp with its smithay, ledger 0015; cosmic-greeter,
0034; cosmic-applets, 0038; cosmic-idle, 0035) are gone with their
Containerfile stages, and so is the "COSMIC on niri" session (0035)
three of them existed for.

What stays, as ordinary Fedora packages: the applications (cosmic-files,
cosmic-term, cosmic-edit, cosmic-store, cosmic-screenshot), cosmic-osd
as the niri (topaz) session's polkit agent (ledger 0041),
xdg-desktop-portal-cosmic for the FileChooser, Screenshot and Settings
portals (ledger 0039), and cosmic-icon-theme, which all of them require.
Each depends on nothing else from COSMIC.

Why: the daily session, niri (topaz), runs no COSMIC shell process and
no fork-built binary. The forks served only the fallback sessions, and
each Fedora COSMIC release (1.10.0 → 1.11.0 on 2026-10-23) demanded a
rebase of all four plus smithay before the weekly input refresh could
merge — a standing cost for sessions nobody logs into. The patch series
remain on the fork branches (`topaz-1.10.0`, `auth-rearm-1.10.0`).

Consequences:

- The login screen offers niri (topaz), niri and GNOME. GNOME is the
  fallback session.
- Everything that existed for a COSMIC session goes with it: the
  `start-cosmic` teardown patch and `topaz-session-shutdown.target`
  (ledger 0036), the cosmic-greeter fingerprint polkit rule (0017), the
  derived COSMIC-on-niri launcher, journal wrapper, workspaces shim,
  startup shim and `cosmic-shell.kdl` include (0035). The baked niri
  config keeps the portal-dialog float rule (0039) inline and no longer
  trusts the COSMIC panel's sandbox engine (0038).
- cosmic-settings leaves too: most of its pages talk to
  cosmic-settings-daemon, and it hard-requires it and cosmic-randr.
- The DDC udev restriction (ledger 0013) stays: the daemon that probed
  blindly is gone, but the rule is a correct default regardless.
- The VM harness tests the niri (topaz) session only.
- The niri fork (ledger 0037), chayang (0046) and the caustics bar
  (0044) are unaffected; the niri-session build stage now builds
  chayang alone.

Verification: `topaz check` asserts none of the session and shell
packages is installed, no COSMIC session entry, fork provenance file,
shim, launcher, teardown target or greeter rule remains, the baked niri
config carries no COSMIC session plumbing, and the three COSMIC pieces
the session relies on (cosmic-osd, the portal backend, cosmic-files as
the apps' representative) are present. The lockfile census (ledger
0022) covers the package set itself.
