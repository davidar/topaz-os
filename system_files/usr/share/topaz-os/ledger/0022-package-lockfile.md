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

`build_files/packages.lock` records the exact package delta relative to
the pinned base image: one `+NEVRA` (added) or `-NEVRA` (removed) line
per package, dependencies included, each followed by its source rpm. The
build does not resolve package names at all — it installs precisely this
closure, fetching any build the mirrors have since dropped from koji's
permanent archive (whose paths derive from the source rpm field), then
censuses the rpm database and fails if the installed delta differs from
the lock. Repository state therefore cannot change or break a build;
package updates happen only when `just lock` (or the weekly
refresh-inputs workflow) re-resolves the intent declared in
build_files/gen-lockfile.sh and the resulting diff is reviewed and
merged.

Together with the base image digest pin and the compositor fork's commit
pin, every package input to the image is now named exactly by the git
tree that builds it.

The lockfile ships at `/usr/share/topaz-os/packages.lock`; `topaz check`
verifies every added NEVRA is installed and every removed one is absent,
on the build gate and on a booted system alike.
