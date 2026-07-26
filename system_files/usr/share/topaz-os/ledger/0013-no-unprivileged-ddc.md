---
title: No unprivileged DDC/CI access to GPU i2c buses
date: 2026-07-26
status: active
paths:
  - /usr/lib/udev/rules.d/60-ddcutil-i2c.rules
---
# No unprivileged DDC/CI access to GPU i2c buses

ddcutil ships a udev rule tagging GPU display-class `i2c-dev` nodes with
`uaccess`, which grants the seated user a passwordless ACL on `/dev/i2c-*`
for the DDC/CI buses behind each display connector. This image removes
that rule.

The immediate reason is a session-killing interaction found on this
hardware (Ryzen 7840HS / Radeon 780M "Phoenix", DCN 3.1.4, PSR-capable
eDP panel). COSMIC sessions froze at the first moment of input idle, on
every kernel/firmware combination tested. The chain, isolated over one
long evening of controlled experiments:

1. `cosmic-settings-daemon`'s brightness module (via the `ddc-hi` crate)
   enumerates every GPU i2c bus about a second after the compositor
   starts, firing raw DDC/CI transactions at all of them — including AUX
   channels of disconnected DP ports. It does this even when the display
   it manages is the internal panel, which it already controls via the
   sysfs backlight.
2. On this platform, a raw AUX transaction to a *disconnected* port,
   performed *before* the eDP's first PSR arming, leaves the display
   core/DMUB in a state where that arming hangs forever mid-entry. The
   same probe after PSR is armed is harmless (verified under GNOME, which
   never probes and is therefore immune in practice).
3. cosmic-comp waits indefinitely on the flip that the stuck PSR arm
   blocks, freezing the session.

Blocking the daemon's bus access — its only path is this rule's ACL — was
verified to produce a fully working COSMIC session with PSR active. The
daemon's legitimate features (internal backlight via logind/sysfs,
brightness keys, theme/battery/locale handling) are unaffected.

Removing unprivileged access is also independently defensible: these
buses carry write-capable traffic to monitor hardware (VCP feature
writes; EDID EEPROMs live on the same wires), and the only consumer on
this image was the probing that caused the freeze. `sudo ddcutil` still
works for deliberate monitor control; GNOME uses none of this.

Interim measure: drop this entry once cosmic-settings-daemon gains probe
hygiene (only touch buses whose connector has a connected sink with an
EDID; skip eDP) or the amdgpu defect is fixed. Upstream reports arising
from the investigation: amdgpu (pre-PSR-arm AUX poisoning), 
cosmic-settings-daemon (blind enumeration), smithay (no flip timeout).
