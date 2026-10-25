#!/bin/bash

# Regenerate build_files/packages.lock (ledger 0022).
#
# This file defines the image's package INTENT: the named packages below
# are resolved (with all dependencies) against the Containerfile's pinned
# base image and today's repositories, and the resulting closure is
# recorded as one line per package: +NEVRA (added) or -NEVRA (removed),
# followed by the package's source rpm. The install script does not resolve
# names at all — it installs exactly this closure, fetching any build the
# mirrors have since dropped from koji (whose archive paths derive from
# the source rpm field). Repository drift therefore cannot change or break
# a build; it only ever appears as a reviewable diff of this file.
#
# Usage: just lock   (or: bash build_files/gen-lockfile.sh)

set -euo pipefail

cd "$(dirname "$0")/.."

base=$(grep -oP '^FROM \Kghcr\.io/ublue-os/\S+' Containerfile)
echo "Resolving package transactions against base: $base" >&2

podman run --rm "$base" bash -euo pipefail -c '
    census() {
        rpm -qa --qf "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH} %{SOURCERPM}\n" \
            | grep -v "^gpg-pubkey" | LC_ALL=C sort
    }
    census > /tmp/pre

    {
        # Weak dependencies are off in every transaction (and in the
        # install scripts, which mirror this): the closure is exactly the
        # named intent plus hard requires, so repository-side Recommends
        # can never grow the image unreviewed. Wanted weak dependencies
        # are named explicitly at the end of this transaction.
        #
        # COSMIC applications and the two session pieces the niri (topaz)
        # session keeps (ledger 0041): cosmic-osd as its polkit agent and
        # the COSMIC portal backend. No COSMIC session or shell (ledger
        # 0047): cosmic-session and everything only it needed are gone.
        # cosmic-settings is the network and Bluetooth UI of the niri
        # (topaz) session (the bar shows state; joining a network needs
        # this); it hard-requires cosmic-settings-daemon and cosmic-randr,
        # two leaf packages that nothing starts.
        dnf5 -y install --setopt=install_weak_deps=False \
            cosmic-files \
            cosmic-term \
            cosmic-edit \
            cosmic-store \
            cosmic-screenshot \
            cosmic-settings \
            cosmic-osd \
            cosmic-icon-theme \
            xdg-desktop-portal-cosmic
        # Wanted weak dependencies, promoted to explicit intent: playerctl
        # for media-key bindings. (The Qt theming and spell-checking
        # packages left with the kde-connect subtree — its apps were the
        # only native Qt applications in the image; the topaz-home
        # kdeconnect recipe installs them in its container.)
        dnf5 -y install --setopt=install_weak_deps=False \
            playerctl
        # niri (ledger 0037), with xwayland-satellite for X11 clients (niri
        # has no built-in XWayland).
        dnf5 -y install --setopt=install_weak_deps=False \
            niri \
            xwayland-satellite
        # The "niri (topaz)" session (ledger 0041): the systemd session that
        # ships with niri, the caustics bar (built from source, ledger 0044)
        # and standalone pieces for everything cosmic-session used to
        # supervise; notifications come from the bar, the lock screen is
        # swaylock.
        dnf5 -y install --setopt=install_weak_deps=False \
            swayidle \
            swaylock \
            swaybg \
            fuzzel \
            cliphist
        # The display manager (ledger 0045): tuigreet pulls greetd in.
        dnf5 -y install --setopt=install_weak_deps=False tuigreet
        dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y swap --setopt=install_weak_deps=False libfprint libfprint-tod-goodix
        dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y install --setopt=install_weak_deps=False nethogs
        # A package the transaction needs but the image must not ship
        # would be removed here (rpm -e --nodeps) after this census, and
        # the lock then records it as a transient (~) so the install can
        # fetch the exact build without resolving anything. Nothing needs
        # that today (the last case, cosmic-initial-setup, left with
        # cosmic-session — ledger 0047); the machinery stays.
        census > /tmp/mid
    } >&2

    census > /tmp/post

    LC_ALL=C comm -13 /tmp/pre /tmp/post | sed "s/^/+/"
    LC_ALL=C comm -23 /tmp/pre /tmp/post | sed "s/^/-/"
    LC_ALL=C comm -13 /tmp/pre /tmp/mid | LC_ALL=C comm -23 - /tmp/post | sed "s/^/~/"
' > build_files/packages.lock

echo "Wrote build_files/packages.lock:" >&2
{
    grep -c '^+' build_files/packages.lock | xargs echo "  added:  " >&2
    grep -c '^-' build_files/packages.lock | xargs echo "  removed:" >&2
    grep -c '^~' build_files/packages.lock | xargs echo "  transient:" >&2
} || true
