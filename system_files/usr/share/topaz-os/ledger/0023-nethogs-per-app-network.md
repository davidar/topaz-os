---
title: nethogs with packet-capture capabilities for per-app network monitoring
date: 2026-08-09
status: active
paths:
  - /usr/sbin/nethogs
---
# nethogs with packet-capture capabilities

Per-process network attribution requires packet capture, which no sandboxed
application can do: flatpak system monitors (Mission Center is the one that
prompted this) delegate to a host `nethogs` binary carrying the needed file
capabilities. On mutable distros Mission Center offers to install and
`setcap` nethogs itself; on an image-based system that helper flow fails
against the immutable `/usr`, so the image ships the equivalent.

The build installs `nethogs` (via the package lockfile) and grants
`cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe` — the
same capability set Mission Center's helper applies. The capabilities ride
the image as `security.capability` xattrs, which ostree preserves; `topaz
check` asserts the exact `getcap` output so a capability-stripping regression
anywhere in the pipeline (rpm, ostree commit, rechunk) fails the build.

Verified end to end 2026-08-09 on a transient `bootc usroverlay` before
baking: with the capabilities in place, Mission Center's per-app network
columns populate without further configuration.

The capability set is scoped to the `nethogs` binary, not granted to any
user or service; nothing runs by default. Anyone with shell access could
already observe interface-level traffic — this adds per-process
attribution for tools that ask for it.
