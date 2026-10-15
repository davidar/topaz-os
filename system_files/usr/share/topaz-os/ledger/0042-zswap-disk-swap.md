---
title: Swap reaches the disk through zswap; zram retired
date: 2026-10-15
status: active
paths:
  - /etc/systemd/zram-generator.conf
  - /usr/lib/tmpfiles.d/topaz-zswap.conf
  - /usr/lib/systemd/system/topaz-swapfile.service
  - /usr/lib/systemd/system/var-swap-swapfile.swap
  - /usr/libexec/topaz/swapfile
  - /usr/lib/systemd/system-preset/45-topaz.preset
---
# Swap reaches the disk through zswap; zram retired

Fedora's default swap is a zram device: a compressed pool in RAM, capped
at 8 GiB, and the only place swapped pages can go. Cold memory therefore
never leaves RAM. Once the pool is full, reclaim has nowhere to put the
next page and the OOM killer becomes the sole release valve — even when
most of what fills the pool is memory nothing has touched in days.
Pages that do not compress (compiled artifacts, media, VM guest memory)
sit in the pool at full size, making it worse. The zram writeback
feature does not help on its own: nothing in the kernel drives it, and
without `CONFIG_ZRAM_TRACK_ENTRY_ACTIME` it cannot tell old pages from
new.

The image replaces this with zswap over a disk swapfile:

- `topaz-swapfile.service` creates `/var/swap/swapfile` on first boot
  (sized to RAM, rounded up to whole GiB, capped at 32 GiB; its own
  btrfs subvolume so it is never snapshotted), and
  `var-swap-swapfile.swap` activates it. The unit is preset-enabled and
  enabled in the built image; the file itself is runtime state, so
  `/var` still ships empty.
- `topaz-zswap.conf` (tmpfiles.d) enables zswap with zstd and the LRU
  shrinker. Swapped pages are compressed into a RAM pool first, at zram
  speed; as the pool fills or memory pressure rises, the kernel writes
  the oldest ones to the swapfile and frees the pool. Incompressible
  pages bypass the pool and go straight to disk. The pool size stays at
  the kernel default (20% of RAM).
- `/etc/systemd/zram-generator.conf` is a comment-only file. It takes
  precedence over zram-generator-defaults' config and defines no
  devices; zram and zswap in series would compress every page twice and
  evict to a device that is itself RAM.

This composes with ledger 0027: MGLRU `min_ttl_ms` still kills a
runaway allocation whose working set does not fit, because it only
trips when reclaim would evict pages touched within the last second,
and cold pages aging out to disk are by definition older than that.

Build-time checks: the zram config defines no device, the tmpfiles rule
carries all three parameters, the swap unit is enabled and the creator
script is executable. Runtime (post-boot): `swapon --show` lists the
swapfile and no zram device; `/proc/meminfo` reports `Zswap` and
`Zswapped`; `systemctl status topaz-swapfile.service` on a fresh install.
