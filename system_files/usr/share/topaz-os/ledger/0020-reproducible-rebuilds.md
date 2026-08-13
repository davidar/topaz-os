---
title: Reproducible rebuilds (rpmdb, build-time debris)
date: 2026-07-29
status: active
paths:
  - /usr/share/rpm
  - /usr/lib/sysimage/libdnf5
  - /usr/share/topaz-os/source-date-epoch
  - /usr/lib/authselect/backups
  - /usr/etc/sgml
---
# Reproducible rebuilds (rpmdb, build-time debris)

A rebuild with an unchanged package set must produce an unchanged rpm
database; otherwise the rpmdb layer (~110MB) is invalidated by every
rebuild and dominates otherwise-small updates.

Four sources of byte-churn, all eliminated:

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
  stays readable on a booted image. The conversion runs on a tmpfs copy
  rather than in place (in-place sqlite page writes through an overlayfs
  copy-up once committed a torn database, 2026-08-12), the result is
  integrity-checked so a torn database fails its own layer before it can
  be committed or cached, and each layer refuses to build if rpm reports
  any error reading the database it inherited.
- `authselect select --force` (the fingerprint PAM profile, ledger 0006)
  snapshots the files it replaces into a timestamped, random-suffixed
  directory under `/usr/lib/authselect/backups/`, baking a fresh name
  into every build. The build passes `--nobackup` — a container build
  has no prior configuration worth restoring.
- the docbook-dtds `%post` (reached through kde-connect's kf6-kdoctools
  dependency) generates the `/etc/sgml` catalogs with libxml2's
  `xmlcatalog`, which serializes SGML catalogs from a hash table seeded
  per process — a fresh line order on every install. The lines only
  delegate to disjoint per-DTD catalogs, so order carries no meaning;
  the build sorts each catalog into a canonical order.
- the build's dnf transactions leave per-repo `countme` cookies under
  `/var/lib/dnf`. Fedora's privacy-preserving user counting draws a
  random request budget and stamps window epochs into each cookie, so
  the bytes differ between otherwise identical builds — and sometimes
  collide, which made rebuild comparisons flicker between one and two
  differing layers (root-caused 2026-08-09 by object-diffing the
  unpackaged chunks of two same-content builds). Fixed as part of the
  general rule that the image ships an empty `/var` (ledger 0024).

Beyond byte-churn, the CI build environment has silently corrupted
files outright (2026-08-13, found by diffing two published images whose
sources differed by one documentation file): files rewritten in place
through an overlayfs copy-up were committed with their new size but old
or missing data blocks (`authselect.conf` and both XML catalogs, NUL
tails), and a SELinux module store was abandoned mid-transaction after
`rename()` of a lower-layer directory returned `EXDEV` and
libsemanage's non-atomic fallback collided with its own debris — the
`greetd` policy module was silently missing from a published image. The
scriptlets involved swallow these failures, so both the package layers
and `topaz check` verify the state the tools should have left
(well-formed XML catalogs — NUL padding never parses — a debris-free
module store with greetd's module present, the exact authselect state
file) rather than trusting exit codes. The empty `/ctx` bind-mount target that buildah sometimes
commits is removed at the gate; a non-empty one fails the build.

Verification: `topaz check` asserts the topaz-installed packages'
install times sit within the ordinal window of the recorded epoch (an
unclamped transaction overshoots it by weeks), that the shipped rpmdb
is in DELETE journal mode, that no authselect backup directory is
present, that the sgml catalogs are sorted, the torn-state assertions
above, and (in the build container) that `/var` ships empty (ledger
0024); the Containerfile gate additionally asserts the artifact ships
no sidecar files.

The cosmic-comp fork binary (ledger 0015) is outside this entry's
scope: it is recompiled per build and its reproducibility is not
asserted.
