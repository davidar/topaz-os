---
title: distrobox pytorch app image updated
date: 2026-07-25
status: active
paths:
  - /etc/distrobox/apps.ini
---
# distrobox pytorch app image updated

The base image's `/etc/distrobox/apps.ini` references
`nvcr.io/nvidia/pytorch:23.08-py3` (August 2023), which is old enough to
produce `GLIBC_ABI_DT_RELR` errors with current nvidia-modprobe — harmless
but noisy, and an old toolchain besides.

The build rewrites it to `pytorch:24.12-py3`. A grep guard in build.sh fails
the build if upstream changes the file such that the rewrite stops matching,
so this entry cannot silently rot. Existing containers must be recreated to
pick up the new image (`distrobox rm <name> --force`, then
`ujust setup-distrobox-app <name>`).
