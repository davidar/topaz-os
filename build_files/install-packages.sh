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

### Packages: COSMIC desktop, fingerprint driver, nethogs
dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9

# The libfprint-tod driver (pinned-version COPR, ledger 0003) conflicts
# with the in-tree libfprint at the file level only, which rpm accepts
# solely when removal and install share one transaction — hence a swap
# rather than lines in the locked install below. The COPR carries a single
# version and the epilogue assert verifies the exact NEVRAs installed, so
# this name-level resolution cannot drift unnoticed; the lockfile records
# the removal.
dnf5 -y swap --setopt=install_weak_deps=False libfprint libfprint-tod-goodix

# cosmic-session Recommends cosmic-wallpapers, which the lock deliberately
# omits (ledger 0025); exclude it so the weak dependency cannot pull an
# unlocked copy into the image.
locked_install /ctx/packages.lock --exclude=cosmic-wallpapers

dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9

# COSMIC installs alongside the base image's GNOME; selectable from the GDM
# session picker. cosmic-greeter comes along as a hard dependency of
# cosmic-session but is not enabled: GDM remains the display manager
# (verified by `topaz check`).

### Trimmed app suite (ledger 0025)
# cosmic-session hard-Requires cosmic-initial-setup, so the transaction
# above installs whatever build the repositories currently carry — the lock
# cannot pin a package that must not ship. The image deliberately has no
# first-boot wizard; remove it post-transaction. --nodeps detaches only
# cosmic-session's dependency entry, and the epilogue census runs after
# this, so any stray it left behind (say, a new unique dependency of a
# future initial-setup build) still fails the gate loudly.
rpm -e --nodeps cosmic-initial-setup

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
