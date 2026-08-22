#!/bin/bash

# niri-session layer: the two binaries the "COSMIC on niri" session needs
# beyond its packaged parts, keyed on the niri-session-build stage's
# output (pinned by COSMIC_ALT_STARTUP_REF and COSMIC_IDLE_REF in the
# Containerfile), plus the fork-built niri from the niri-build stage
# (NIRI_REF) and cosmic-applets from the cosmic-applets-build stage
# (COSMIC_APPLETS_REF).

set -ouex pipefail

### COSMIC on niri (ledger 0035)
# cosmic-session accepts an alternative compositor as its argument;
# cosmic-ext-alternative-startup is the shim niri spawns to report the
# Wayland, X11 and niri socket addresses back to it. It has no packaged
# build, so the image carries one.
#
# cosmic-idle is replaced with the topaz fork, built on the same upstream
# commit Fedora packages: upstream unconditionally binds
# zwlr_output_power_manager_v1 and wp_single_pixel_buffer_manager_v1 and
# aborts when either is missing. niri implements neither, so the packaged
# binary dies at session start and takes idle locking and idle suspend
# with it; the fork draws the fade through a wl_shm buffer and powers the
# screen through niri's own IPC. Guard: fail loudly when Fedora bumps
# cosmic-idle, so the fork is rebased onto the new source rather than
# silently shadowing it.
idle_base_version=1.5.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-idle)
if [ "$packaged_version" != "$idle_base_version" ]; then
    echo "cosmic-idle is now $packaged_version but the fork is based on $idle_base_version" >&2
    echo "Rebase the cosmic-idle fork and update COSMIC_IDLE_REF" >&2
    exit 1
fi
install -m0755 /niri-session/cosmic-ext-alternative-startup \
    /usr/bin/cosmic-ext-alternative-startup
install -m0755 /niri-session/cosmic-idle /usr/bin/cosmic-idle

### niri topaz fork (ledger 0037)
# The packaged niri binary is replaced by the topaz fork, built on the
# same upstream release. Everything else from the niri package (session
# files, systemd units, default config, docs) stays. Guard: fail loudly
# when Fedora bumps niri, so the fork is rebased onto the new release and
# NIRI_REF moved.
niri_base_version=26.04
packaged_niri=$(rpm -q --qf '%{VERSION}' niri)
if [ "$packaged_niri" != "$niri_base_version" ]; then
    echo "niri is now $packaged_niri but the fork is based on $niri_base_version" >&2
    echo "Rebase the niri fork and update NIRI_REF" >&2
    exit 1
fi
install -m0755 /niri-build/niri /usr/bin/niri

### COSMIC dock on niri (ledger 0038)
# cosmic-applets is a multicall binary; /usr/bin/cosmic-app-list and the
# other applet names are symlinks into it, so replacing the one binary
# covers every applet. Same guard as above: a Fedora version bump fails
# the build until the fork is rebased and COSMIC_APPLETS_REF moved.
applets_base_version=1.5.0
packaged_applets=$(rpm -q --qf '%{VERSION}' cosmic-applets)
if [ "$packaged_applets" != "$applets_base_version" ]; then
    echo "cosmic-applets is now $packaged_applets but the fork is based on $applets_base_version" >&2
    echo "Rebase the cosmic-applets fork and update COSMIC_APPLETS_REF" >&2
    exit 1
fi
test -L /usr/bin/cosmic-app-list
install -m0755 /cosmic-applets-build/cosmic-applets /usr/bin/cosmic-applets

{ cat /niri-session/build-info; echo "idle_base=$idle_base_version";
  cat /niri-build/build-info; echo "niri_base=$niri_base_version";
  cat /cosmic-applets-build/build-info; echo "applets_base=$applets_base_version"; } \
    > /usr/share/topaz-os/niri-session-build
