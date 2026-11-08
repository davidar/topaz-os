---
title: Locked builder toolchains (niri-build.lock, caustics-build.lock)
date: 2026-11-08
status: active
paths:
  - /usr/share/topaz-os/niri-build.lock
  - /usr/share/topaz-os/caustics-build.lock
---
# Locked builder toolchains (niri-build.lock, caustics-build.lock)

niri (ledger 0037) and the caustics set (ledgers 0044, 0049) are
compiled in two fedora stages of the Containerfile. Until 2026-11-08
each stage installed its toolchain with a bare `dnf install`, so the
compiler was whatever Fedora's updates repository held on the day the
stage last built — and the build cache kept that stage until something
else invalidated it. The image published on 2026-11-03 carried a niri
compiled by rustc 1.99.0 from a stage cached weeks before; the weekly
reproducibility rebuild of 2026-11-07, cold by design, installed rustc
1.99.1-2 and gcc 16.2.1-3 and produced different bytes for every Rust
binary while every package layer matched. The compiler was an input
nothing named.

Each stage now has a lock of its own, `build_files/niri-build.lock` and
`build_files/caustics-build.lock`, in the package lock's format (ledger
0022): the stage's packages resolved by `just lock` against the
Containerfile's pinned fedora digest, weak dependencies off, one
`+NEVRA` line per package with its source rpm. The stage installs that
closure exactly, through the same download-then-install path as the
image's package layer (`build_files/install-builder.sh`), and fails if
the installed delta differs from the lock. A toolchain update is now a
reviewable diff that rebuilds niri and the caustics set on purpose, and
the Saturday rebuild compiles with the compiler the release did.

The weekly refresh-inputs workflow regenerates the builder locks with
the package lock, and owns the fedora digest the builder stages start
from: the digest and the locks resolved against it move in one commit,
as the base digest and the package lock do, so Renovate no longer bumps
it alone.

The locks ship at `/usr/share/topaz-os/`, and each stage records the
rustc it installed in `/usr/share/topaz-os/niri-session-build`
(`niri_rustc`, `caustics_rustc`).

Check: for niri and the caustics bar, the recorded rustc is the build
the stage's shipped lock names, and the binary carries the Fedora build
stamp rustc embeds.
