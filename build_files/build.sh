#!/bin/bash

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

### COSMIC desktop
# Installed alongside the base image's GNOME; selectable from the GDM session
# picker. cosmic-greeter comes along as a hard dependency of cosmic-session
# but is not enabled: GDM remains the display manager (verified by
# `topaz check`).
dnf5 -y install \
    cosmic-session \
    cosmic-comp \
    cosmic-panel \
    cosmic-launcher \
    cosmic-applets \
    cosmic-app-library \
    cosmic-settings \
    cosmic-settings-daemon \
    cosmic-bg \
    cosmic-files \
    cosmic-term \
    cosmic-edit \
    cosmic-store \
    cosmic-screenshot \
    cosmic-osd \
    cosmic-notifications \
    cosmic-idle \
    cosmic-randr \
    cosmic-workspaces \
    cosmic-icon-theme \
    cosmic-wallpapers \
    cosmic-config-fedora

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

### Fingerprint reader support (Goodix 27c6:550a)
# The in-tree libfprint has no driver for this sensor; swap in libfprint-tod
# plus the Goodix TOD driver from COPR.
dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9
dnf5 -y swap libfprint libfprint-tod-goodix
dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9

### earlyoom
# Intervenes on memory pressure earlier than systemd-oomd; configuration in
# system_files/etc/default/earlyoom adds a swap threshold to catch thrashing.
dnf5 -y install earlyoom
systemctl enable earlyoom.service

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
authselect select custom/local-custom \
    with-fingerprint with-silent-lastlog with-mdns4 --force

### supergfxd (GPU mode switching)
# Preset shipped in system_files; enable in the built image as well so the
# guarantee does not depend on first-boot preset application.
systemctl enable supergfxd.service
