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

1. fetch the image with podman (parallel layer downloads) into root's
   container storage,
2. `bootc switch --transport containers-storage` to import it locally,
3. switch back to the registry reference so automatic updates keep
   tracking it — a no-op fetch, every layer is already imported,
4. remove the temporary podman copy.

With no argument it fetches the current bootc origin; passing a
registry reference makes it a fast tag switch. Disk usage doubles while
the image transiently exists in both stores. For small incremental
updates the serial fetch is fine — the verb earns its keep on tag
switches and the first pull after a layer-scheme change.
