#!/bin/bash

# niri-session layer: the fade tool of the niri (topaz) session, keyed on
# the niri-session-build stage's output (pinned by CHAYANG_REF in the
# Containerfile), plus the fork-built niri from the niri-build stage
# (NIRI_REF) and the caustics set, bar and canvas, from the
# caustics-build stage (CAUSTICS_REF).

set -ouex pipefail

### chayang, the fade before the idle lock (ledger 0046)
# Built from the upstream commit Fedora packages as 0.1.0 with the wl_shm
# fallback patch in build_files/patches/, because niri does not export
# wp_single_pixel_buffer_manager_v1 and the packaged binary exits before
# drawing anything. The package itself stays out of the lock, so nothing
# is shadowed; fail loudly if it ever arrives as a dependency.
if rpm -q chayang >/dev/null 2>&1; then
    echo "chayang is installed as a package; the image builds its own (ledger 0046)" >&2
    exit 1
fi
install -m0755 /niri-session/chayang /usr/bin/chayang

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

### caustics bar and canvas (ledgers 0044, 0049)
# One set: the sixteen binaries under /usr/lib/caustics-bar/<abi-hash>/
# and, in /usr/bin, a symlink into it for each binary something
# outside the set starts by name: the bar and the canvas (their units)
# and the canvas's client (the wallpaper script). Each host resolves its
# own path and starts its sidecars beside it, so the links are what make
# the set a set. The shaders are compiled in; no sources ship (the reload
# sidecars idle without a directory to watch).
caustics_set=$(sed -n 's/^caustics_set=//p' /caustics-build/build-info)
test -d "/caustics-build/lib/caustics-bar/$caustics_set"
mkdir -p /usr/lib/caustics-bar
cp -r "/caustics-build/lib/caustics-bar/$caustics_set" /usr/lib/caustics-bar/
for b in caustics-bar caustics-canvas caustics-canvasctl; do
    ln -s "/usr/lib/caustics-bar/$caustics_set/$b" "/usr/bin/$b"
done
[ "$(/usr/bin/caustics-bar --abi-hash)" = "$caustics_set" ]

{ cat /niri-session/build-info;
  cat /niri-build/build-info; echo "niri_base=$niri_base_version";
  cat /caustics-build/build-info; } \
    > /usr/share/topaz-os/niri-session-build
