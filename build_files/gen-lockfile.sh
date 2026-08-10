#!/bin/bash

# Regenerate build_files/packages.lock and build_files/packages-kde.lock
# (ledger 0022).
#
# These files define the image's package INTENT: the named packages below
# are resolved (with all dependencies) against the Containerfile's pinned
# base image and today's repositories, and the resulting closure is
# recorded as one line per package: +NEVRA (added) or -NEVRA (removed),
# followed by the package's source rpm. The install scripts do not resolve
# names at all — they install exactly this closure, fetching any build the
# mirrors have since dropped from koji (whose archive paths derive from
# the source rpm field). Repository drift therefore cannot change or break
# a build; it only ever appears as a reviewable diff of these files.
#
# Two lockfiles because the package set ships as two content-keyed layers
# (main, then kde-connect — see the Containerfile): the censuses below run
# at the same boundary the layers split at, so each lock keys exactly one
# layer.
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
        # cosmic-session Recommends cosmic-wallpapers; excluded rather than
        # merely unlisted so the weak dependency cannot pull it back in
        # (ledger 0025).
        dnf5 -y install --exclude=cosmic-wallpapers \
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
        dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y swap libfprint libfprint-tod-goodix
        dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y install earlyoom
        dnf5 -y install nethogs
        # cosmic-session hard-Requires cosmic-initial-setup, but the image
        # deliberately ships no first-boot wizard (ledger 0025): drop it
        # after the transaction. --nodeps detaches only the dependency
        # entry, and the census below never records the package.
        rpm -e --nodeps cosmic-initial-setup
    } >&2

    census > /tmp/mid

    dnf5 -y install kde-connect >&2

    census > /tmp/post

    LC_ALL=C comm -13 /tmp/pre /tmp/mid | sed "s/^/+/"
    LC_ALL=C comm -23 /tmp/pre /tmp/mid | sed "s/^/-/"
    echo "== packages-kde.lock =="
    LC_ALL=C comm -13 /tmp/mid /tmp/post | sed "s/^/+/"
    LC_ALL=C comm -23 /tmp/mid /tmp/post | sed "s/^/-/"
' | awk -v out=build_files/packages.lock '
    /^== packages-kde\.lock ==$/ { out = "build_files/packages-kde.lock"; next }
    { print > out }
'

for lock in build_files/packages.lock build_files/packages-kde.lock; do
    echo "Wrote $lock:" >&2
    {
        grep -c '^+' "$lock" | xargs echo "  added:  " >&2
        grep -c '^-' "$lock" | xargs echo "  removed:" >&2
    } || true
done
