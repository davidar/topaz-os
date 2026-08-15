#!/bin/bash

# Configuration layer: topaz system files plus every patch and enablement
# applied on top of the installed package set. This is the layer that
# changes most often, and it is kilobytes — keeping it last means a config
# or ledger edit re-ships almost nothing.

set -ouex pipefail

# Copy system_files/ from the repo into the image
cp -avf "/ctx/system_files"/. /

### Image identity (os-release)
# GRUB titles boot entries with os-release PRETTY_NAME, so without this the
# booted topaz-os deployment and its Bluefin rollback render as identical
# menu lines. Rebrand NAME and PRETTY_NAME only; ID, ID_LIKE, VARIANT_ID,
# IMAGE_ID and the rest stay Bluefin's so tooling keyed on them still works.
# Guard: fail loudly if the base image reshapes the fields we rewrite
grep -q '^NAME="Bluefin"' /usr/lib/os-release
grep -q '^PRETTY_NAME="Bluefin ' /usr/lib/os-release
base_version=$(. /usr/lib/os-release && echo "$IMAGE_VERSION")
sed -i \
    -e 's/^NAME=.*/NAME="topaz-os"/' \
    -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"topaz-os (Bluefin $base_version)\"/" \
    /usr/lib/os-release

### No passwordless DDC/CI access to GPU i2c buses
# cosmic-settings-daemon's brightness module blindly DDC-probes every GPU
# i2c bus (including disconnected DP ports) about a second after the
# compositor starts. On this hardware (amdgpu DCN 3.1.4, PSR eDP), a raw
# AUX transaction to a disconnected port before the panel's first PSR
# arming wedges that arming forever, freezing COSMIC at the first idle —
# ledger 0013 has the full investigation. The daemon reaches /dev/i2c-*
# through seat-user ACLs granted by udev `uaccess` rules; two base-image
# packages ship one. Closing both (and the wider unprivileged-DDC surface)
# leaves `sudo ddcutil` and OpenRGB's non-i2c device access working. Drop
# once the daemon probes politely. Guards: fail the build if either rule
# moves or changes shape upstream; `topaz check` additionally sweeps the
# whole rules directory for any i2c uaccess grant.
grep -q 'SUBSYSTEM=="i2c-dev".*TAG+="uaccess"' \
    /usr/lib/udev/rules.d/60-ddcutil-i2c.rules
rm /usr/lib/udev/rules.d/60-ddcutil-i2c.rules
grep -q '^KERNEL=="i2c-\[0-99\]\*", TAG+="uaccess"$' \
    /usr/lib/udev/rules.d/60-openrgb.rules
sed -i '/^KERNEL=="i2c-\[0-99\]\*", TAG+="uaccess"$/d' \
    /usr/lib/udev/rules.d/60-openrgb.rules

### Fingerprint-friendly PAM stack (authselect)
# The default fingerprint PAM flow blocks password entry until fprintd times
# out (30s). Generate a custom profile from the base `local` profile: every
# file is a symlink back to the base, so upstream profile changes flow through
# automatically, except system-auth, which is copied and patched to set
# timeout=5 so the password prompt appears after 5s if the reader is unused.
authselect create-profile local-custom --base-on local \
    --symlink-meta --symlink-nsswitch --symlink-dconf --symlink-pam
rm /etc/authselect/custom/local-custom/system-auth
cp /usr/share/authselect/default/local/system-auth \
    /etc/authselect/custom/local-custom/system-auth
# Guard: fail the build if upstream reshaped the pam_fprintd line
grep -Eq 'pam_fprintd\.so\s+\{include if "with-fingerprint"\}' \
    /etc/authselect/custom/local-custom/system-auth
sed -i 's/pam_fprintd\.so/pam_fprintd.so timeout=5/' \
    /etc/authselect/custom/local-custom/system-auth
# --nobackup: the automatic backup bakes a timestamped directory into the
# image, invalidating an otherwise-unchanged layer on every rebuild
# (ledger 0020); in a container build there is no prior state to restore.
authselect select custom/local-custom \
    with-fingerprint with-silent-lastlog with-mdns4 --force --nobackup

### supergfxd (GPU mode switching)
# Preset shipped in system_files; enable in the built image as well so the
# guarantee does not depend on first-boot preset application.
systemctl enable supergfxd.service

### KDE Connect firewall ports (ledger 0030)
# KDE Connect itself runs from a distrobox (topaz-home's kdeconnect
# recipe; ledger 0026 records the eviction), but the container shares the
# host network namespace, so the host firewall must still pass its
# discovery and transfer ports. The service definition (TCP/UDP
# 1714-1764) ships with firewalld; open it in the default zone.
firewall-offline-cmd --zone=FedoraWorkstation --add-service=kdeconnect

### Partial image pulls (ledger 0031)
# CI publishes the image as zstd:chunked (see build.yml); flip the
# containers-storage default so podman pulls fetch only the files not
# already present in local storage. `topaz pull` stages updates through
# podman, so this is the client half of delta updates. Patch the shipped
# default rather than adding an /etc/containers/storage.conf override —
# an override copy would shadow every future base change to the file.
grep -q '^# enable_partial_images = "false"$' /usr/share/containers/storage.conf
sed -i 's|^# enable_partial_images = "false"$|enable_partial_images = "true"|' \
    /usr/share/containers/storage.conf

### Empty /var (ledger 0024)
# The package layer already scrubbed its own debris; assert the tmpfiles.d
# fragment that replaces the one functional /var item (greetd's
# xdg-desktop-portal mask, recreated at boot) is among the shipped files,
# and re-scrub as insurance against this layer's own tooling — the
# check/lint gate in the Containerfile is the authority on what ships.
grep -q 'xdg-desktop-portal.service - - - - /dev/null' \
    /usr/lib/tmpfiles.d/topaz-greetd-portal-mask.conf
for p in /var/* /var/.[!.]* /run/* /run/.[!.]*; do
    [ -e "$p" ] || continue
    findmnt -n "$p" > /dev/null && continue
    rm -rf "$p" 2>/dev/null || true
done
mkdir -p /var/tmp
