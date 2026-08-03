---
title: Locked package set (packages.lock)
date: 2026-08-03
status: active
paths:
  - /usr/share/topaz-os/packages.lock
---
# Locked package set (packages.lock)

The build's dnf transactions resolve against whatever the Fedora
repositories (and one COPR) hold at build time, so two builds of the same
commit can install different package versions — silent drift the image's
other reproducibility measures (ledger 0020) cannot see.

`build_files/packages.lock` records the exact package delta the build is
allowed to produce relative to the pinned base image: one `+NEVRA` line
per added package (dependencies included) and one `-NEVRA` line per
removed package. build.sh censuses the rpm database before and after its
transactions and fails the build if the resolved delta differs from the
lockfile. Repository drift therefore surfaces as a reviewable lockfile
diff in git history instead of changing the image unreviewed; refresh
with `just lock` (build_files/gen-lockfile.sh replays the transactions
against the pinned base).

Together with the base image digest pin and the compositor fork's commit
pin, every package input to the image is now named exactly by the git
tree that builds it.

The lockfile ships at `/usr/share/topaz-os/packages.lock`; `topaz check`
verifies every added NEVRA is installed and every removed one is absent,
on the build gate and on a booted system alike.
