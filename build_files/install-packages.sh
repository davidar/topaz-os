#!/bin/bash

# Package layer: the locked package set, plus everything derived purely
# from the installed set: nethogs capabilities, reproducibility fixups,
# /var scrub. Keyed on packages.lock (plus this
# script and the shared lib), so it is invalidated only when one of those
# changes — edits to system files or configuration rebuild only the later,
# kilobyte-sized layers.

set -ouex pipefail

# shellcheck source=build_files/locked-install.lib.sh
source /ctx/locked-install.lib.sh

### Reproducible package installs (ledger 0020)
clamp_install_times
# Record the derived epoch so `topaz check` can verify installs were
# clamped. rpm stamps each package SOURCE_DATE_EPOCH plus a small
# install-order ordinal that keeps accumulating across both package
# layers, so all clamped times sit within a few hundred seconds of this
# first layer's value.
mkdir -p /usr/share/topaz-os
printf '%s\n' "$SOURCE_DATE_EPOCH" > /usr/share/topaz-os/source-date-epoch

### Locked package set, prologue (ledger 0022)
census > /tmp/rpm-pre.list

### Packages: the locked set, fingerprint driver, nethogs
dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9

# The libfprint-tod driver (pinned-version COPR, ledger 0003) conflicts
# with the in-tree libfprint at the file level only, which rpm accepts
# solely when removal and install share one transaction — hence a swap
# rather than lines in the locked install below. The COPR carries a single
# version and the epilogue assert verifies the exact NEVRAs installed, so
# this name-level resolution cannot drift unnoticed; the lockfile records
# the removal.
dnf5 -y swap --setopt=install_weak_deps=False libfprint libfprint-tod-goodix

locked_install /ctx/packages.lock

dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9

### nethogs (ledger 0023)
# Per-process network accounting needs packet capture, which the tool gets
# via file capabilities instead of running as root. This is the exact
# capability set Mission Center's own helper installer applies on mutable
# distros; granting it here lets sandboxed monitors (which cannot hold
# these capabilities themselves) delegate to the host binary. Capabilities
# ride the image as security.capability xattrs, verified by `topaz check`.
setcap 'cap_net_admin,cap_net_raw,cap_dac_read_search,cap_sys_ptrace+pe' \
    /usr/sbin/nethogs

### Locked package set, epilogue (ledger 0022)
verify_layer_delta /ctx/packages.lock /tmp/rpm-pre.list

commit_clean_layer
