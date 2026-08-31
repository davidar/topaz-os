---
title: Known-bad kernels refused; base tracks Bluefin's latest kernel
date: 2026-08-31
status: active
paths:
  - /usr/lib/modules
---
# Known-bad kernels refused; base tracks Bluefin's latest kernel

The base image ships the kernel, and the weekly input refresh (ledger
0022) follows a Bluefin tag wherever it goes. Two things changed after
the first kernel regression this image shipped.

**The base follows `latest`, not `stable`.** Bluefin's two tracks build
the same userland; they differ only in which kernel is installed.
`stable` takes the Fedora CoreOS stable-stream kernel, about two weeks
behind Fedora, on the theory that the soak catches regressions. It
catches server-shaped ones. A desktop-GPU regression sails through —
nothing in that stream scans out to a Radeon panel — so for this
hardware the gate delayed the bug by two weeks and then delayed the fix
by two more, while `latest` (Fedora's own kernel, security fixes and
all) had already moved past it. Fedora's kernel cadence is the better
place to stand for a laptop image; `latest` also moves to each new
Fedora release at GA rather than a month later, which only brings the
rebase obligations of ledgers 0015, 0034, 0037 and 0038 forward.

**Releases with a known regression are refused.** `topaz check` asserts
the installed kernel's version-release matches no denylisted pattern —
at build time against the image, so a refresh that would ship such a
kernel fails its gate instead of publishing, and at runtime against the
booted deployment, where a failure means the running kernel is one this
image would refuse. The pattern in the check is the denylist; this entry
records why each release is on it and when it comes off.

- **7.1.6 and 7.1.7** — amdgpu display regression: transient blocks of
  noise on screen during large redraws (window moves, video, terminal
  scrolling), produced at scanout — a screenshot of the affected frame
  is clean. Affects the Phoenix APU (Radeon 780M, DCN 3.1.4) among
  others; first seen on this machine on the first boot of a 7.1.6 image
  (Bluefin stable 44.20260825). Red Hat bug 2512106, drm/amd work item
  5567 (suspected commit `ac11060c6d49`, "drm/amd/display: Handle struct
  drm_plane_state.ignore_damage_clips"); fixed in 7.1.8-200.fc44 by two
  stable backports. Drop the pattern once the base has moved past 7.1.8.
