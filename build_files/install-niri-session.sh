#!/bin/bash

# niri-session layer: the two binaries the "COSMIC on niri" session needs
# beyond its packaged parts, keyed on the niri-session-build stage's
# output (pinned by COSMIC_ALT_STARTUP_REF and COSMIC_IDLE_REF in the
# Containerfile), plus the patched niri from the niri-build stage
# (NIRI_REF).

set -ouex pipefail

### COSMIC on niri (ledger 0035)
# cosmic-session accepts an alternative compositor as its argument;
# cosmic-ext-alternative-startup is the shim niri spawns to report the
# Wayland, X11 and niri socket addresses back to it. It has no packaged
# build, so the image carries one.
#
# cosmic-idle is replaced with a build of the same upstream commit Fedora
# packages, plus one patch: upstream unconditionally binds
# zwlr_output_power_manager_v1 and wp_single_pixel_buffer_manager_v1 and
# aborts when either is missing. niri implements neither, so the packaged
# binary dies at session start and takes idle locking and idle suspend
# with it; patched, the fade uses a wl_shm buffer and screen power goes
# through niri's own IPC. Guard: fail loudly when Fedora bumps
# cosmic-idle, so the patch is re-verified against the new source rather
# than silently shadowing it.
patch_base_version=1.5.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-idle)
if [ "$packaged_version" != "$patch_base_version" ]; then
    echo "cosmic-idle is now $packaged_version but the patch is based on $patch_base_version" >&2
    echo "Re-verify build_files/cosmic-idle-niri-compat.patch and update COSMIC_IDLE_REF" >&2
    exit 1
fi
install -m0755 /niri-session/cosmic-ext-alternative-startup \
    /usr/bin/cosmic-ext-alternative-startup
install -m0755 /niri-session/cosmic-idle /usr/bin/cosmic-idle

### niri with configurable swipe distances (ledger 0037)
# The packaged niri binary is replaced by a build of the same upstream
# release with build_files/niri-topaz.patch applied. Everything
# else from the niri package (session files, systemd units, default
# config, docs) stays. Guard: fail loudly when Fedora bumps niri, so the
# patch is re-verified against the new source and NIRI_REF moved.
niri_base_version=26.04
packaged_niri=$(rpm -q --qf '%{VERSION}' niri)
if [ "$packaged_niri" != "$niri_base_version" ]; then
    echo "niri is now $packaged_niri but the patch is based on $niri_base_version" >&2
    echo "Re-verify build_files/niri-topaz.patch and update NIRI_REF" >&2
    exit 1
fi
install -m0755 /niri-build/niri /usr/bin/niri

### COSMIC dock on niri (ledger 0038)
# cosmic-applets is a multicall binary; /usr/bin/cosmic-app-list and the
# other applet names are symlinks into it, so replacing the one binary
# patches every applet. Same guard as above: a Fedora version bump fails
# the build until the patch is re-verified and COSMIC_APPLETS_REF moved.
applets_base_version=1.5.0
packaged_applets=$(rpm -q --qf '%{VERSION}' cosmic-applets)
if [ "$packaged_applets" != "$applets_base_version" ]; then
    echo "cosmic-applets is now $packaged_applets but the patch is based on $applets_base_version" >&2
    echo "Re-verify build_files/cosmic-applets-niri-dock.patch and update COSMIC_APPLETS_REF" >&2
    exit 1
fi
test -L /usr/bin/cosmic-app-list
install -m0755 /cosmic-applets-build/cosmic-applets /usr/bin/cosmic-applets

{ cat /niri-session/build-info; echo "idle_base=$patch_base_version";
  cat /niri-build/build-info; echo "niri_base=$niri_base_version";
  cat /cosmic-applets-build/build-info; echo "applets_base=$applets_base_version"; } \
    > /usr/share/topaz-os/niri-session-build
