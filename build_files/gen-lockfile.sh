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
        # cosmic-session Recommends cosmic-wallpapers; excluded rather than
        # merely unlisted so the weak dependency cannot pull it back in
        # (ledger 0025).
        dnf5 -y install --setopt=install_weak_deps=False \
            --exclude=cosmic-wallpapers \
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
            cosmic-config-fedora
        # Wanted weak dependencies, promoted to explicit intent: playerctl
        # backs the media keys in cosmic-settings-daemon. (The Qt theming
        # and spell-checking packages left with the kde-connect subtree —
        # its apps were the only native Qt applications in the image; the
        # topaz-home kdeconnect recipe installs them in its container.)
        dnf5 -y install --setopt=install_weak_deps=False \
            playerctl
        dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y swap --setopt=install_weak_deps=False libfprint libfprint-tod-goodix
        dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y install --setopt=install_weak_deps=False nethogs
        # cosmic-session hard-Requires cosmic-initial-setup, but the image
        # deliberately ships no first-boot wizard (ledger 0025): drop it
        # after the transaction. --nodeps detaches only the dependency
        # entry, and the census below never records the package.
        rpm -e --nodeps cosmic-initial-setup
    } >&2

    census > /tmp/post

    LC_ALL=C comm -13 /tmp/pre /tmp/post | sed "s/^/+/"
    LC_ALL=C comm -23 /tmp/pre /tmp/post | sed "s/^/-/"
' > build_files/packages.lock

echo "Wrote build_files/packages.lock:" >&2
{
    grep -c '^+' build_files/packages.lock | xargs echo "  added:  " >&2
    grep -c '^-' build_files/packages.lock | xargs echo "  removed:" >&2
} || true
