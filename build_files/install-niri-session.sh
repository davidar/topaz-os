#!/bin/bash

# niri-session layer: the two binaries the "COSMIC on niri" session needs
# beyond its packaged parts, keyed on the niri-session-build stage's
# output (pinned by COSMIC_ALT_STARTUP_REF and COSMIC_IDLE_REF in the
# Containerfile).

set -ouex pipefail

### COSMIC on niri (ledger 0035)
# cosmic-session accepts an alternative compositor as its argument;
# cosmic-ext-alternative-startup is the shim niri spawns to report the
# Wayland, X11 and niri socket addresses back to it. It has no packaged
# build, so the image carries one.
#
# cosmic-idle is replaced with a build of the same upstream commit Fedora
# packages, plus one patch: upstream unconditionally binds
# zwlr_output_power_manager_v1 and aborts when it is missing. niri does
# not implement that protocol, so the packaged binary dies at session
# start and takes idle locking and idle suspend with it; patched, screens
# simply stay powered (the fade-to-black surface still covers them).
# Guard: fail loudly when Fedora bumps cosmic-idle, so the patch is
# re-verified against the new source rather than silently shadowing it.
patch_base_version=1.5.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-idle)
if [ "$packaged_version" != "$patch_base_version" ]; then
    echo "cosmic-idle is now $packaged_version but the patch is based on $patch_base_version" >&2
    echo "Re-verify build_files/cosmic-idle-optional-output-power.patch and update COSMIC_IDLE_REF" >&2
    exit 1
fi
install -m0755 /niri-session/cosmic-ext-alternative-startup \
    /usr/bin/cosmic-ext-alternative-startup
install -m0755 /niri-session/cosmic-idle /usr/bin/cosmic-idle
{ cat /niri-session/build-info; echo "idle_base=$patch_base_version"; } \
    > /usr/share/topaz-os/niri-session-build
