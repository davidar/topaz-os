#!/bin/bash

# KDE Connect layer: the kde-connect subtree as its own content-keyed
# layer, keyed on packages-kde.lock (plus this script and the shared lib).
#
# Separate from the main package layer because the two halves churn on
# different clocks: the Qt/KF6 stack rebuilds near-weekly in Fedora while
# the COSMIC set moves at COSMIC release cadence, and their dependency
# graphs are disjoint. A kde-only lock bump re-ships this layer (~420 MiB,
# rpm database copy included) instead of the whole ~1 GiB package layer.
# This layer comes after the main one because rpm database contamination
# flows downward: each package layer's diff carries the database as
# mutated so far, so the frequent churner must sit last for the layer
# above it to stay byte-identical. It is also the layer that disappears
# outright if KDE Connect ever gets a Flathub channel (ledger 0019 records
# why it is baked at all).

set -ouex pipefail

# shellcheck source=build_files/locked-install.lib.sh
source /ctx/locked-install.lib.sh

clamp_install_times

census > /tmp/rpm-pre.list

locked_install /ctx/packages-kde.lock

verify_layer_delta /ctx/packages-kde.lock /tmp/rpm-pre.list

commit_clean_layer
