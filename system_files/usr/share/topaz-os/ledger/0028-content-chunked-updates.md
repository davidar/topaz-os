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
at this rewrite stage, not at build time: podman folds `--label`
values into the final stage's step cache keys, so any per-invocation
value — the wall-clock `created` stamp, commit-specific URLs — forced
every layer in the target stage to rebuild, defeating the CI layer
cache and quietly turning the post-gate cache push into a second,
ungated build. The build is now label-free, and label timestamps
derive from the commit rather than the wall clock, so rechunking the
same commit reproduces the same manifest bit-for-bit. Labels the base
image declares are carried through unchanged unless overridden here.
