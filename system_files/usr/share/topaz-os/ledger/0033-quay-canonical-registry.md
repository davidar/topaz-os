---
title: quay.io is the canonical registry; GHCR is a best-effort mirror
date: 2026-08-15
status: active
paths:
  - .github/workflows/build.yml
---
# quay.io is the canonical registry; GHCR is a best-effort mirror

The partial pulls that make updates cheap (ledger 0031) fetch blob
segments with multi-range HTTP requests. GHCR rejects those outright
(`501 Unsupported client range` — it serves only single explicit
ranges), and current podman aborts the pull on that answer instead of
degrading, so against GHCR the delta path could never engage. quay.io
serves every request shape the client emits (verified with the real
patterns: two-range table-of-contents fetches, twenty-range body reads,
open-ended tail ranges), and a live update through it moved 1 MiB where
the same update as a plain fetch moves gigabytes.

CI therefore publishes to quay.io first — push, tag aliases
(`build_files/alias-tags.sh`), and the cosign signature all target the
quay image — and then mirrors the same bytes to GHCR as a separate
best-effort step: it verifies the mirrored digest matches the canonical
one exactly, but its failure never blocks a release. Publishing away
from GitHub also decouples serving from building: machines can still
fetch updates while GitHub is down, and a quay outage only pauses
updates that GHCR-side full pulls (or the next timer run) pick up
later. The mirror carries no separate signature; verification is
against the canonical quay reference.

Client-side, the podman abort-on-501 and the missing single-range
strategy are upstream containers/image material — if either lands, the
GHCR mirror becomes a fully usable fallback rather than a full-pull
one.
