---
title: Reproducible package installs (deterministic rpmdb)
date: 2026-07-29
status: active
paths:
  - /usr/share/rpm
  - /usr/lib/sysimage/libdnf5
  - /usr/share/topaz-os/source-date-epoch
---
# Reproducible package installs (deterministic rpmdb)

A rebuild with an unchanged package set must produce an unchanged rpm
database; otherwise the rpmdb layer (~110MB) is invalidated by every
rebuild and dominates otherwise-small updates.

Two sources of byte-churn, both eliminated:

- rpm stamps wall-clock `INSTALLTIME`/`INSTALLTID` into each install
  transaction. With `SOURCE_DATE_EPOCH` set, rpm instead assigns the
  epoch plus an install-order ordinal, deterministic for a fixed package
  set. The build exports the epoch, derived from the base image's newest
  install time so it changes only when the base does, and records it at
  `/usr/share/topaz-os/source-date-epoch`.
- sqlite `-wal`/`-shm` sidecar files hold nondeterministic runtime state
  and are recreated by any rpm invocation — including the build gate's
  own checks — so the Containerfile drops them in its final step, after
  the gate. On a booted system `/usr` is read-only and they stay absent.

Verification: `topaz check` asserts the topaz-installed packages'
install times sit within the ordinal window of the recorded epoch (an
unclamped transaction overshoots it by weeks); CI asserts the published
artifact contains no sidecar files.

The cosmic-comp fork binary (ledger 0015) is outside this entry's
scope: it is recompiled per build and its reproducibility is not
asserted.
