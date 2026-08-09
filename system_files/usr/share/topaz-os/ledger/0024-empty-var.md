---
title: image ships an empty /var
date: 2026-08-09
status: active
paths:
  - /var
  - /usr/lib/tmpfiles.d/topaz-greetd-portal-mask.conf
---
# image ships an empty /var

`/var` is machine state. At deploy time the image's copy is factory
content, materialized once on the first deployment of a stateroot and
never touched by updates again — so anything the build leaves there is
dead weight in every image pull, and a reproducibility hazard besides:
the build's own dnf transactions were fossilizing per-repo `countme`
cookies (randomized request budgets, wall-clock window epochs) that made
otherwise identical rebuilds diverge (ledger 0020).

The base image gets this right: its `/var` contains a single empty
`/var/tmp`. This entry brings the topaz delta to the same standard. The
build ends by clearing `/var` (and the runtime-only `/run`, which
collected dnf and selinux tooling debris) down to that same skeleton,
and the one functional item our package set put there — the greetd
package's xdg-desktop-portal mask, a symlink inside the greeter user's
home directory — moves to a `tmpfiles.d` fragment in `/usr`, recreated
declaratively at boot. `bootc container lint`, which warns about
exactly this class of stray content, suggested the tmpfiles entries
verbatim; the Containerfile has run it since the rechunk migration, but
only advisorily — it now runs with `--fatal-warnings`, so newly
introduced debris fails the build instead of warning into a log nobody
reads.

Verification: `topaz check` asserts (in the build container) that
nothing but the empty `/var/tmp` ships, and that the portal-mask
tmpfiles fragment is present; `bootc container lint --fatal-warnings`
gates the build on the same class of problem image-wide. Existing
deployments are unaffected — their `/var` was populated at install time
and is machine state; the tmpfiles entry is idempotent over the mask
the old factory copy already placed. Post-boot verification: greeter
session shows no xdg-desktop-portal unit for the greetd user.
