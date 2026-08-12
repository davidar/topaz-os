---
title: Kill memory hogs fast instead of thrashing
date: 2026-08-12
status: active
paths:
  - /usr/lib/tmpfiles.d/topaz-mglru.conf
  - /usr/lib/sysctl.d/99-topaz-sysrq.conf
  - /usr/lib/systemd/oomd.conf.d/topaz.conf
---
# Kill memory hogs fast instead of thrashing

A runaway allocation used to thrash-lock the desktop for a minute before
systemd-oomd intervened — and oomd's pgscan-based ranking then killed
the biggest bystander (the browser) rather than the allocator. earlyoom
(formerly ledger 0001) never fired at all: it triggers on MemAvailable,
which counts reclaimable page cache and therefore stays high throughout
a thrash spiral. It was removed as a false sense of security.

Three declarative configs make memory exhaustion resolve in about a
second instead. Verified with a deliberate unbounded allocator: MGLRU
killed it at 21 GiB with no perceptible hiccup, while the compositor
and browser ran on untouched.

- MGLRU `min_ttl_ms=1000` (tmpfiles.d): if reclaim would evict a
  working set younger than one second, the kernel OOM-kills the top
  consumer instead of thrashing. ChromeOS ships this value; mainline
  leaves the knob at 0 (off) by default.
- `kernel.sysrq=1` (sysctl.d): Alt+PrtSc+F is the manual escape hatch —
  a kernel-level OOM kill that works while userspace is frozen.
- systemd-oomd pressure duration 5s (oomd.conf.d): the PSI-based
  backstop acts in seconds, not the 20s default.
