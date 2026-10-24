---
title: COSMIC forks retired; COSMIC-on-niri session removed
date: 2026-10-25
status: active
paths:
  - /usr/bin/cosmic-comp
  - /usr/bin/cosmic-greeter
  - /usr/bin/cosmic-applets
  - /usr/bin/cosmic-idle
  - /usr/share/wayland-sessions/cosmic.desktop
  - /etc/niri/config.kdl
---
# COSMIC forks retired; COSMIC-on-niri session removed

Every COSMIC binary in the image is Fedora's again. The four forks the
image built from source — cosmic-comp with its smithay (ledger 0015),
cosmic-greeter (0034), cosmic-applets (0038) and cosmic-idle (0035) —
and their Containerfile stages are gone, along with the "COSMIC on niri"
session (0035) that three of them existed for.

Why now: the daily session, niri (topaz) (ledger 0041), runs no COSMIC
shell process and no fork-built COSMIC binary. The one COSMIC process
left in it, cosmic-osd as the polkit agent, is an unforked leaf package.
The forks served only the two fallback sessions, and each Fedora COSMIC
release (1.10.0 → 1.11.0 on 2026-10-23) demanded a rebase of all four
plus smithay before the weekly input refresh could merge — a standing
cost for sessions nobody logs into. The patch series remain on the fork
branches (`topaz-1.10.0`, `auth-rearm-1.10.0`) for reference.

What this changes:

- The stock COSMIC session stays as a fallback next to GNOME, on
  Fedora's binaries: no gesture tunables, no startup retry on a busy DRM
  device, no fingerprint re-arm or lock-lifecycle fixes in its locker.
- The COSMIC-on-niri session entry, the launcher derived from
  `start-cosmic`, the journal wrapper, the workspaces shim, the startup
  shim and the `/etc/niri/cosmic-shell.kdl` include are removed. The
  baked niri config keeps the portal-dialog float rule (ledger 0039)
  inline and no longer trusts the COSMIC panel's sandbox engine.
- The VM harness tests the niri (topaz) session only.
- The niri fork (ledger 0037), chayang (0046) and the caustics bar
  (0044) are unaffected; the niri-session build stage now builds
  chayang alone.

Verification: `topaz check` asserts that none of the four binaries
differs from its package (rpm verification), that no fork provenance
file, shim, derived launcher or session entry remains, and that the
baked niri config carries no COSMIC session plumbing. The lockfile
census (ledger 0022) is unchanged: the package set is the same, only
the binaries written over it are not.
