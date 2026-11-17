#!/bin/bash

# Builder stage toolchain (ledger 0052): install exactly the closure the
# stage's lock records, the way the image's package layer installs its
# own (ledger 0022), so the compiler that builds niri and the caustics
# set is named by the tree and moves only with a reviewed lock diff.
#
#   install-builder.sh /ctx/<stage>.lock
#
# The lock travels with the stage's output too, to ship under
# /usr/share/topaz-os/ where `topaz check` reads it.

set -ouex pipefail

# shellcheck source=build_files/locked-install.lib.sh
source /ctx/locked-install.lib.sh

lock=$1
census > /tmp/rpm-pre.list
locked_install "$lock"
verify_layer_delta "$lock" /tmp/rpm-pre.list
dnf5 clean all
install -Dm0644 "$lock" "/out/$(basename "$lock")"
