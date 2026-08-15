---
title: Updates publish as zstd:chunked for partial pulls
date: 2026-08-15
status: active
paths:
  - .github/workflows/build.yml
---
# Updates publish as zstd:chunked for partial pulls

Content-based layers (ledger 0028) cut update downloads to the layers
that changed, but a layer still re-downloads whole when any byte in it
moves — including bytes that only moved between layers. Measured on a
real update (one package subtree removed): 2,485 MiB re-downloaded of
which ~2.2 GiB was repacking collateral, files the machine already had.

CI now recompresses the chunked image to zstd:chunked before pushing:
identical layers (the uncompressed digests are untouched, so the weekly
reproducibility check is unaffected), but every blob carries a table of
contents that lets the client see which files it already has and fetch
only the rest via HTTP range requests. With partial pulls enabled in
containers-storage, the same update measured 35.8 MiB — dedup at file
granularity absorbs both repacking collateral and unchanged files
inside genuinely-changed layers.

The conversion is a single `skopeo copy` into an OCI directory from
which every alias tag is pushed, so tags share blobs and the cosign
signature (applied after the push) covers exactly what was published.
Conversion output is deterministic for the pinned skopeo (verified
serial vs 16-way parallel); the pin is Renovate-managed, and any drift
a bump introduces surfaces in the weekly check's layer comparison.

Plain consumers are unaffected: ostree/bootc's native fetcher ingests a
zstd:chunked-only image completely (verified against this image), it
just doesn't benefit until it grows partial-pull support
([bootc#20](https://github.com/bootc-dev/bootc/issues/20)).
