#!/usr/bin/bash
# Lay out the test disk the way installers lay out machines, then install
# the image into it. Runs as root inside the test image's own container
# (lib.sh build_disk mounts this file and the output directory), where
# bootc and the filesystem tools are the image's.
#
# The layout is the one bootc-image-builder gives disk_config/disk.toml
# and Fedora's installer gives a laptop: a BIOS boot stub, an ESP, a 1 GiB
# ext4 /boot and a btrfs root mounted from a `root` subvolume. `bootc
# install to-disk` would make an ESP and one root with /boot a directory
# on it, and a guest with no boot.mount would never catch a regression in
# that part of the boot. bootc writes the /boot line of the deployment's
# fstab itself and takes rootflags=subvol=root from the mount; the ESP
# line is added here.
set -euo pipefail

disk=${1:?disk image path}
# Generous slack: deploying the ~13 GB image onto a 30 GiB btrfs root
# tripped ostree's min-free-space guard, the known btrfs free-space
# misreporting class (ostreedev/ostree#1688). Sparse, so the size is free.
truncate -s 40G "$disk"

# --partscan: without it the kernel refuses to reread a loop device's
# partition table and no partition nodes ever appear.
dev=$(losetup --find --show --partscan "$disk")
mnt=/run/install-root
cleanup() {
    umount -R "$mnt" 2>/dev/null || true
    losetup -d "$dev" 2>/dev/null || true
}
trap cleanup EXIT

sfdisk --quiet "$dev" <<EOF
label: gpt
size=1MiB, type=21686148-6449-6E6F-744E-656564454649, bootable
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
size=1GiB, type=BC13C2FF-59E6-4262-A352-B275FD6F7172
type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
EOF
# The partition nodes come from the host's udev through the /dev mount.
for _ in $(seq 1 50); do
    [ -b "${dev}p4" ] && break
    sleep 0.2
done
[ -b "${dev}p4" ] || { echo "install-disk: no partition nodes for $dev" >&2; exit 1; }

mkfs.vfat -F 32 -n EFI-SYSTEM "${dev}p2" >/dev/null
mkfs.ext4 -q -L boot "${dev}p3"
mkfs.btrfs -q -L root "${dev}p4"

mkdir -p "$mnt"
mount "${dev}p4" "$mnt"
btrfs subvolume create "$mnt/root" >/dev/null
umount "$mnt"
mount -o subvol=root "${dev}p4" "$mnt"
mkdir -p "$mnt/boot"
mount "${dev}p3" "$mnt/boot"
mkdir -p "$mnt/boot/efi"
mount "${dev}p2" "$mnt/boot/efi"

# --generic-image: every bootloader, no firmware changes, as for any disk
# meant for a VM. The console kargs feed the serial log. On a host
# without SELinux (the GitHub runners) bootc notes "host-disabled" and
# labels the target from its own policy; the guest boots enforcing.
bootc install to-filesystem --generic-image --skip-fetch-check \
    --karg console=tty0 --karg console=ttyS0 "$mnt"

# The ESP's fstab line, as the installer writes it; bootc wrote /boot's.
# bootc leaves the root remounted read-only when it finalizes; one write
# needs it back.
mount -o remount,rw "$mnt"
deploy=$(echo "$mnt"/ostree/deploy/default/deploy/*.0)
[ -d "$deploy" ] || { echo "install-disk: no deployment under $mnt" >&2; exit 1; }
esp_uuid=$(blkid -s UUID -o value "${dev}p2")
echo "UUID=$esp_uuid /boot/efi vfat umask=0077,shortname=winnt 0 2" >> "$deploy/etc/fstab"
echo "install-disk: fstab of the deployment:"
sed 's/^/    /' "$deploy/etc/fstab"
