#!/bin/bash

set -ouex pipefail

# Copy system_files/ from the repo into the image
cp -avf "/ctx/system_files"/. /

### COSMIC desktop
# Installed alongside the base image's GNOME; selectable from the GDM session
# picker. cosmic-greeter is intentionally omitted to keep GDM as the display
# manager.
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
