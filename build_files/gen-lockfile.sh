#!/bin/bash

# Regenerate build_files/packages.lock (ledger 0022).
#
# This file defines the image's package INTENT: the named packages below
# are resolved (with all dependencies) against the Containerfile's pinned
# base image and today's repositories, and the resulting closure is
# recorded as one line per package: +NEVRA (added) or -NEVRA (removed),
# followed by the package's source rpm. build.sh does not resolve names at
# all — it installs exactly this closure, fetching any build the mirrors
# have since dropped from koji (whose archive paths derive from the source
# rpm field). Repository drift therefore cannot change or break a build;
# it only ever appears as a reviewable diff of this file.
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
        dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y swap libfprint libfprint-tod-goodix
        dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9
        dnf5 -y install earlyoom
        dnf5 -y install kde-connect
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
