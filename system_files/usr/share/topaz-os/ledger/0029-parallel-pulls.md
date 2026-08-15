---
title: Parallel update fetches (topaz pull)
date: 2026-08-12
status: active
paths:
  - /usr/bin/topaz
---
# Parallel update fetches (topaz pull)

bootc downloads image layers serially through its image proxy — measured
at ~80 Mbps on a 500 Mbps link — and content-based layer splitting
(ledger 0028) raises the layer count from ~80 to ~400, adding a round
trip per layer. Upstream tracks the real fix
([bootc#20](https://github.com/bootc-dev/bootc/issues/20)); until it
lands, `topaz pull` packages the proven workaround as one verb:

1. fetch the image with podman (parallel layer downloads, and partial
   pulls of the zstd:chunked artifact — ledger 0031) into root's
   container storage,
2. `bootc switch --transport containers-storage` to import it locally,
3. switch back to the registry reference so automatic updates keep
   tracking it — a no-op fetch, every layer is already imported,
4. keep the podman copy as the delta base for the next partial pull
   (~5 GiB standing cost in /var), reclaiming only the copy it
   supersedes.

With no argument it fetches the current bootc origin; passing a
registry reference makes it a fast tag switch. When the registry digest
is already staged or booted the verb exits without touching anything,
so it is safe to run unconditionally from a timer (ledger 0032). The
image keeps existing in both stores; that duplication is what makes the
next update a delta.
