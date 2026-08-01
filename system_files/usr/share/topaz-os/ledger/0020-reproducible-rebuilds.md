---
title: Reproducible rebuilds (rpmdb, build-time debris)
date: 2026-07-29
status: active
paths:
  - /usr/share/rpm
  - /usr/lib/sysimage/libdnf5
  - /usr/share/topaz-os/source-date-epoch
  - /usr/lib/authselect/backups
---
# Reproducible rebuilds (rpmdb, build-time debris)

A rebuild with an unchanged package set must produce an unchanged rpm
database; otherwise the rpmdb layer (~110MB) is invalidated by every
rebuild and dominates otherwise-small updates.

Three sources of byte-churn, all eliminated:

- rpm stamps wall-clock `INSTALLTIME`/`INSTALLTID` into each install
  transaction. With `SOURCE_DATE_EPOCH` set, rpm instead assigns the
  epoch plus an install-order ordinal, deterministic for a fixed package
  set. The build exports the epoch, derived from the base image's newest
  install time so it changes only when the base does, and records it at
  `/usr/share/topaz-os/source-date-epoch`.
- sqlite `-wal`/`-shm` sidecar files hold nondeterministic runtime state
  and are recreated by any rpm invocation for as long as the database is
  in WAL journal mode. They cannot simply be deleted either: a WAL-mode
  database without its sidecars is unopenable from read-only `/usr`,
  breaking every rpm query on the booted system. The build instead
  checkpoints each database and converts it to DELETE journal mode after
  the last write — reads no longer create sidecars, and the database
  stays readable on a booted image.
- `authselect select --force` (the fingerprint PAM profile, ledger 0006)
  snapshots the files it replaces into a timestamped, random-suffixed
  directory under `/usr/lib/authselect/backups/`, baking a fresh name
  into every build. The build passes `--nobackup` — a container build
  has no prior configuration worth restoring.

Verification: `topaz check` asserts the topaz-installed packages'
install times sit within the ordinal window of the recorded epoch (an
unclamped transaction overshoots it by weeks), that the shipped rpmdb
is in DELETE journal mode, and that no authselect backup directory is
present; CI asserts the published artifact contains no sidecar files.

The cosmic-comp fork binary (ledger 0015) is outside this entry's
scope: it is recompiled per build and its reproducibility is not
asserted.
