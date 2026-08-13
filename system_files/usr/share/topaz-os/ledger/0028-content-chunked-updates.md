---
title: Updates ship as content-based layers
date: 2026-08-12
status: active
paths:
  - .github/workflows/build.yml
  - build_files/chunk-image.sh
  - Justfile
---
# Updates ship as content-based layers

The Containerfile builds a few coarse content-keyed layers (packages,
kde-connect, compositor, config) — the right shape for build caching,
the wrong shape for updates: dropping a single package re-shipped the
whole ~900 MiB locked install, plus the kde layer stacked on its rpm
database, with each package layer dragging a ~139 MiB rpmdb copy along.

After the build gate passes, CI rewrites the image into ~400
content-based layers with [chunkah](https://github.com/coreos/chunkah)
(successor to rpm-ostree's `build-chunked-oci`; Fedora CoreOS is
adopting the same tool): roughly one layer per package, the rpm
database isolated in its own, so a machine downloads only the packages
that actually changed. Measured on a real update (one package removed,
two updated): 1218 MiB before, 262 MiB after, of which only ~19 MiB was
repacking collateral.

The rewrite is deterministic (`SOURCE_DATE_EPOCH=0`, matching the
build's `--timestamp 0`), verified by the weekly job that rebuilds the
unchanged tree and requires zero layer divergence from the published
image. The chunked artifact is a plain bootc image: the pre-chunk
`ostree.commit`/`ostree.final-diffid` labels describe a layer set that
no longer exists and are stripped, per chunkah's documented bootc
recipe.

Image labels (version, source URLs, ArtifactHub metadata) are stamped
at this rewrite stage rather than at build time: they describe the
published artifact, and deriving their timestamps from the commit
rather than the wall clock keeps the rewrite deterministic — chunking
the same commit twice reproduces the manifest bit-for-bit, which the
wall-clock `created` stamp had silently broken. The build itself is
label-free. Labels the base image declares are carried through
unchanged unless overridden here.

The commit timestamp is also stamped as the manifest annotation
`org.opencontainers.image.created` (chunkah drops the base's manifest
annotations just as it drops labels): bootc derives the deployment's
ostree commit timestamp from that annotation, falling back to the
config's `created` field — which `SOURCE_DATE_EPOCH=0` pins to the
epoch, leaving the deployment with timestamp zero and crashing
rpm-ostree's status printer. Raising `SOURCE_DATE_EPOCH` itself is not
an option: it is also the mtime clamp for layer contents, and
directory mtimes in extracted image storage are extraction wall-clock,
so a per-commit epoch would re-stamp every directory entry and churn
every layer on every update. The annotation carries the real timestamp
with zero layer impact.
