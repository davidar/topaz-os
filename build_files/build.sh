#!/bin/bash

set -ouex pipefail

# Copy system_files/ from the repo into the image
cp -avf "/ctx/system_files"/. /

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
