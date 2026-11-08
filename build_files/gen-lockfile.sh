#!/bin/bash

# Regenerate build_files/packages.lock (ledger 0022) and the builder
# stages' toolchain locks (ledger 0052).
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
# The same holds for the compilers: each builder stage's packages are
# resolved against the Containerfile's pinned fedora digest and recorded
# in build_files/<stage>.lock, which the stage installs exactly.
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
        # COSMIC applications, as ordinary packages; no COSMIC session,
        # shell or session piece (ledger 0047): cosmic-session and
        # everything only it needed are gone, cosmic-osd left with the
        # polkit agent of the canvas (ledger 0050) and the COSMIC portal
        # backend with the portal rewiring onto gtk and gnome (ledger
        # 0039), taking cosmic-screenshot, its one client, with it.
        # cosmic-settings is the network and Bluetooth UI of the niri
        # (topaz) session (the bar shows state; joining a network needs
        # this); it hard-requires cosmic-settings-daemon and cosmic-randr,
        # two leaf packages that nothing starts. cosmic-launcher is the
        # application launcher bound to Mod+D; it brings pop-launcher and
        # qalculate, nothing else.
        dnf5 -y install --setopt=install_weak_deps=False \
            cosmic-files \
            cosmic-term \
            cosmic-edit \
            cosmic-store \
            cosmic-settings \
            cosmic-launcher \
            cosmic-icon-theme
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
        # ships with niri, the caustics bar and canvas (built from source,
        # ledgers 0044, 0049) and standalone pieces for the rest of what
        # cosmic-session used to supervise; notifications come from the
        # bar, the wallpaper, the lock screen and the polkit prompt from the
        # canvas (swaybg, swaylock and cosmic-osd, its rescues, left in
        # ledger 0050).
        dnf5 -y install --setopt=install_weak_deps=False \
            swayidle \
            fuzzel \
            cliphist
        # Terminal settings tools (ledger 0051): the session has no settings
        # application and no toolkit; what the bar and the canvas do not
        # cover is done in a terminal, locally or over ssh. One tool per
        # domain, all packaged: network connections, audio routing, output
        # layout and hotplug profiles, colour temperature, screenshots and
        # recording, processes, disk usage and removable mounts. Nothing is
        # enabled; kanshi and wlsunset are daemons a user starts.
        dnf5 -y install --setopt=install_weak_deps=False \
            NetworkManager-tui \
            wiremix \
            kanshi \
            wlr-randr \
            wlsunset \
            grim \
            slurp \
            wf-recorder \
            btop \
            ncdu \
            gdu \
            bashmount
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

# Builder toolchains (ledger 0052). The fork-built niri and the caustics
# set are compiled in fedora stages whose packages used to come from a
# bare `dnf install`: the compiler moved with Fedora's updates repository,
# invisibly, because the build cache kept the old stage until a cold
# rebuild (the reproducibility rebuild of 2026-11-07 compiled every Rust
# binary with a rustc one point release newer than the published image's).
# Each stage's packages are resolved here against the Containerfile's
# pinned fedora digest, weak dependencies off like the image's, and
# recorded as a lock of their own, which the stage installs exactly
# (build_files/install-builder.sh). The package names are the stage's
# intent; this is the only place they are written.
builder_lock() { # <stage> <packages...>
    local stage=$1 image
    shift
    image=$(grep -oP "^FROM \Kregistry\.fedoraproject\.org/fedora:\S+(?= AS ${stage}$)" Containerfile)
    echo "Resolving the $stage toolchain against: $image" >&2
    podman run --rm "$image" bash -euo pipefail -c '
        census() {
            rpm -qa --qf "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH} %{SOURCERPM}\n" \
                | grep -v "^gpg-pubkey" | LC_ALL=C sort
        }
        census > /tmp/pre
        dnf5 -y install --setopt=install_weak_deps=False "$@" >&2
        census > /tmp/post
        LC_ALL=C comm -13 /tmp/pre /tmp/post | sed "s/^/+/"
        LC_ALL=C comm -23 /tmp/pre /tmp/post | sed "s/^/-/"
    ' builder-lock "$@" > "build_files/$stage.lock"
    echo "Wrote build_files/$stage.lock: $(grep -c '^+' "build_files/$stage.lock") added" >&2
}

# diffutils is for the install script's own delta assertion (the fedora
# image ships without it); the rest is each stage's build.
# niri (ledger 0037): Rust plus the C libraries its crates bind.
builder_lock niri-build \
    diffutils gcc cargo rust clang glibc-devel pkgconf-pkg-config git-core \
    cairo-devel dbus-devel mesa-libgbm-devel gdk-pixbuf2-devel glib2-devel \
    gtk4-devel libadwaita-devel libdisplay-info-devel libinput-devel \
    pipewire-devel libseat-devel systemd-devel pango-devel wayland-devel \
    libxkbcommon-devel
# caustics (ledgers 0044, 0049): Rust and a C compiler for its build
# scripts; gcc requires glibc-devel, so the headers come with it.
builder_lock caustics-build diffutils gcc cargo rust git-core pkgconf-pkg-config
