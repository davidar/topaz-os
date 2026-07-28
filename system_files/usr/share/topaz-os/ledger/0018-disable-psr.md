---
title: Disable eDP Panel Self Refresh (amdgpu PSR)
date: 2026-07-28
status: active
paths:
  - /usr/lib/bootc/kargs.d/10-topaz-display.toml
---
# Disable eDP Panel Self Refresh (amdgpu PSR)

`amdgpu.dcdebugmask=0x10` is added to the kernel command line via bootc's
`kargs.d` mechanism (the same one the base image uses for its NVIDIA
arguments), turning off Panel Self Refresh on the internal display.

This is the second entry in the PSR wedge saga. Ledger 0013 closed a
deterministic trigger: userspace AUX/i2c probes hitting a disconnected
DP port before the session's first PSR arm would poison DMUB firmware
state, and the first PSR entry then hung forever (`DMCUB error` +
`flip_done timed out`, display dead until reboot). That fix held — but
two further hard freezes (2026-07-27 and 2026-07-28, both mid-session
under COSMIC, roughly an hour of awake time after a suspend/resume)
produced the identical death signature with the i2c doors closed. Same
terminal state, different door.

The remaining trigger is probabilistic and not fully proven, but the
differential against GNOME is stark: months of GNOME on identical
hardware without a single wedge, versus two in two days of COSMIC.
mutter structurally cannot use overlay planes (its plane-assignment
code asserts on the overlay type), while smithay's `DrmCompositor`
assigns and removes overlay planes frame-by-frame — and MPO racing PSR
transitions is a known-fragile path in amdgpu's display firmware.
A second hard freeze also costs more than a session: it skips ostree's
staged-deployment finalization, silently discarding any pending update.

Rather than chase each door, this entry removes the wedge state itself:
with PSR never armed, PSR entry cannot hang. `dcdebugmask=0x10` is the
standard, widely deployed amdgpu workaround for the broader PSR bug
family. Measured cost is on the order of 1W while the screen is static
(display pipe, ~2.5 GB/s of scanout memory traffic, and shallower SoC
idle states); there is no functional or visual change.

Revisit if an amdgpu/DMUB fix lands upstream, or once a
compositor-side flip watchdog makes wedges recoverable enough to trade
reliability back for the idle power.

Build-time check: the kargs.d file exists and carries the argument.
Post-boot verification: `grep amdgpu.dcdebugmask /proc/cmdline`.
