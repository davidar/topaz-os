#!/bin/bash

# Regenerate build_files/packages.lock (ledger 0022).
#
# Runs the image's package transactions against the Containerfile's pinned
# base image and today's repositories, and records the resulting package
# delta as one +NEVRA (added) or -NEVRA (removed) line per package,
# dependencies included. build.sh performs the same transactions and fails
# the build if its resolved delta differs from the committed lockfile, so
# repository drift surfaces as a reviewable lockfile diff instead of
# silently changing the image.
#
# The transaction list below MUST mirror build.sh's dnf5 calls. The two
# cannot drift silently: a mismatch changes the resolved delta, and the
# build's lockfile assertion fails until they agree again.
#
# Usage: just lock   (or: bash build_files/gen-lockfile.sh)

set -euo pipefail

cd "$(dirname "$0")/.."

base=$(grep -oP '^FROM \Kghcr\.io/ublue-os/\S+' Containerfile)
echo "Resolving package transactions against base: $base" >&2

podman run --rm "$base" bash -euo pipefail -c '
    census() {
        rpm -qa --qf "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n" \
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
