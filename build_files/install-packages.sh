#!/bin/bash

# Package layer: the locked package set, plus everything derived purely
# from the installed set: nethogs capabilities, reproducibility fixups,
# /var scrub. Keyed on packages.lock (plus this
# script and the shared lib), so it is invalidated only when one of those
# changes — edits to system files or configuration rebuild only the later,
# kilobyte-sized layers.

set -ouex pipefail

# shellcheck source=build_files/locked-install.lib.sh
source /ctx/locked-install.lib.sh

### Reproducible package installs
clamp_install_times
# Record the derived epoch so `topaz check` can verify installs were
# clamped. rpm stamps each package SOURCE_DATE_EPOCH plus a small
# install-order ordinal that keeps accumulating across both package
# layers, so all clamped times sit within a few hundred seconds of this
# first layer's value.
mkdir -p /usr/share/topaz-os
printf '%s\n' "$SOURCE_DATE_EPOCH" > /usr/share/topaz-os/source-date-epoch

### Locked package set, prologue
census > /tmp/rpm-pre.list

### Packages: the locked set, fingerprint driver, nethogs
dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9

# The libfprint-tod driver (pinned-version COPR) conflicts
# with the in-tree libfprint at the file level only, which rpm accepts
# solely when removal and install share one transaction — hence a swap
# rather than lines in the locked install below. The COPR carries a single
# version and the epilogue assert verifies the exact NEVRAs installed, so
# this name-level resolution cannot drift unnoticed; the lockfile records
# the removal.
dnf5 -y swap --setopt=install_weak_deps=False libfprint libfprint-tod-goodix

locked_install /ctx/packages.lock

dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9

### nethogs
# Per-process network accounting needs packet capture, which the tool gets
# via file capabilities instead of running as root. This is the exact
# capability set Mission Center's own helper installer applies on mutable
# distros; granting it here lets sandboxed monitors (which cannot hold
# these capabilities themselves) delegate to the host binary. Capabilities
# ride the image as security.capability xattrs, verified by `topaz check`.
setcap 'cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe' \
    /usr/sbin/nethogs

### Console font in the initramfs
# The boot log is shown as text in Terminus 12x24, which the kernel
# arguments name (kargs.d/20-topaz-console.toml) and the locked set above
# installs. The base's initramfs carries the stock console fonts only, so
# the font would not load before the root is mounted, and the first
# seconds of the log would be drawn in the kernel's 8x16.
#
# The initramfs is not regenerated. dracut run here reads the whole of
# the final image, and would add what the base's later layers bring but
# its own initramfs does not have (three force-loaded vfio modules,
# multipath and kpartx rules). The font file is appended as a second
# archive instead, which the kernel unpacks after the first: the base's
# initramfs stays a byte-identical prefix, and its size and digest are
# recorded for `topaz check`. Guards: one kernel, the pieces that load a
# console font are in the base's archive, and the font is not.
font=usr/lib/kbd/consolefonts/ter-v24n.psf.gz
test -f "/$font"
kernels=(/usr/lib/modules/*/initramfs.img)
[ "${#kernels[@]}" -eq 1 ]
initramfs=${kernels[0]}
lsinitrd "$initramfs" > /tmp/initramfs.list
grep -q ' usr/lib/kbd/consolefonts$' /tmp/initramfs.list
grep -q ' usr/bin/setfont$' /tmp/initramfs.list
grep -q ' usr/lib/systemd/systemd-vconsole-setup$' /tmp/initramfs.list
grep -q ' usr/lib/udev/rules.d/90-vconsole.rules$' /tmp/initramfs.list
if grep -q " $font\$" /tmp/initramfs.list; then
    echo "the base's initramfs now carries $font; the append is redundant" >&2
    exit 1
fi
printf 'base_size=%s\nbase_sha256=%s\nfont=%s\n' \
    "$(stat -c %s "$initramfs")" \
    "$(sha256sum < "$initramfs" | cut -d' ' -f1)" \
    "$font" > /usr/share/topaz-os/initramfs-font
# A new file renamed into place, not an append: the base's file has a
# second hard link in the image's ostree repository.
cp "$initramfs" "$initramfs.new"
(cd / && printf '%s\n' "$font" |
    cpio --create --format=newc --reproducible --owner=0:0 --quiet) |
    zstd -q >> "$initramfs.new"
chmod 0600 "$initramfs.new"
mv "$initramfs.new" "$initramfs"
rm /tmp/initramfs.list

### Locked package set, epilogue
verify_layer_delta /ctx/packages.lock /tmp/rpm-pre.list

commit_clean_layer
