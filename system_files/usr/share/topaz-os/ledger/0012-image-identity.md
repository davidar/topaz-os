---
title: The image identifies itself as topaz-os, not Bluefin
date: 2026-07-26
status: active
paths:
  - /usr/lib/os-release
  - /etc/os-release
---
# The image identifies itself as topaz-os, not Bluefin

GRUB titles each boot entry with the deployment's os-release `PRETTY_NAME`
(ostree copies it into the BLS entry at deploy time). With os-release
inherited verbatim from the base, the boot menu showed the topaz-os
deployment and its Bluefin rollback as byte-identical lines — e.g.
`Bluefin (Version: 44.20260721)` twice — making it impossible to tell the
custom image from the escape hatch at exactly the moment that distinction
matters (observed on first boot, 2026-07-26).

`configure.sh` rewrites `NAME` and `PRETTY_NAME` to identify the image as
topaz-os, embedding the base Bluefin version it was built from (e.g.
`topaz-os (Bluefin 44.20260721)`). All other fields — `ID=bluefin`,
`ID_LIKE`, `VARIANT_ID`, `IMAGE_ID`, `CPE_NAME`, version fields — are left
untouched: Universal Blue tooling (ujust, uupd, image-info consumers) and
anything else keyed on machine-readable identity should keep treating this
as a Bluefin derivative. `/etc/os-release` is a symlink to the same file,
so both views agree.

Titles are stamped per deployment, so existing entries keep their old
names; the new name appears from the first deployment of a rebranded
image onward.
