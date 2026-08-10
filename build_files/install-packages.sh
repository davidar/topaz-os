#!/bin/bash

# Package layer: everything derived purely from the locked package set.
# This layer is keyed on packages.lock (plus this script), so it is
# invalidated only when the lock changes — edits to system files or
# configuration rebuild only the later, kilobyte-sized layers.

set -ouex pipefail

### Reproducible package installs (ledger 0020)
# rpm stamps wall-clock INSTALLTIME/INSTALLTID into the rpm database, so two
# builds of an identical package set differ byte-wise and the rpmdb's update
# layer churns on every rebuild. rpm honors SOURCE_DATE_EPOCH at install
# time; clamp it to the base image's newest install time so the database
# only changes when the base (or the package set) does.
SOURCE_DATE_EPOCH=$(rpm -qa --qf '%{INSTALLTIME}\n' | sort -n | tail -1)
export SOURCE_DATE_EPOCH
# Record the derived epoch so `topaz check` can verify installs were clamped
# (rpm stamps each package SOURCE_DATE_EPOCH plus a small install-order
# ordinal, so clamped times sit within a few hundred seconds of it)
mkdir -p /usr/share/topaz-os
printf '%s\n' "$SOURCE_DATE_EPOCH" > /usr/share/topaz-os/source-date-epoch

### Locked package set, prologue (ledger 0022)
# Census the base image's packages before the locked install below; the
# epilogue asserts that the delta it produced matches the lockfile exactly.
rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH} %{SOURCERPM}\n' \
    | grep -v '^gpg-pubkey' | LC_ALL=C sort > /tmp/rpm-pre.list

### Packages: COSMIC desktop, fingerprint driver, earlyoom, KDE Connect
# Installed as the exact NEVRA closure recorded in the lockfile — names are
# resolved only when the lock is regenerated (build_files/gen-lockfile.sh,
# which also documents what each group is for; rationale in ledgers 0001,
# 0003, 0004, 0019, 0022). Fedora's repositories drop superseded builds, so
# any locked package the mirrors no longer serve is fetched from koji,
# which keeps every build permanently at a path derived from its source rpm
# (the lockfile's second field).
dnf5 -y copr enable antiderivative/libfprint-tod-goodix-0.0.9

# The libfprint-tod driver (pinned-version COPR, ledger 0003) conflicts
# with the in-tree libfprint at the file level only, which rpm accepts
# solely when removal and install share one transaction — hence a swap
# rather than lines in the locked install below. The COPR carries a single
# version and the epilogue assert verifies the exact NEVRAs installed, so
# this name-level resolution cannot drift unnoticed; the lockfile records
# the removal.
dnf5 -y swap libfprint libfprint-tod-goodix

awk '/^\+/ { print substr($1, 2), $2 }' /ctx/packages.lock > /tmp/lock.adds

# Availability check on epoch-less name-ver-rel.arch (epoch never affects
# what a mirror serves); anything missing gets a koji URL instead.
# shellcheck disable=SC2046 # NEVRAs contain no whitespace; splitting is wanted
dnf5 -q repoquery --queryformat '%{name}-%{version}-%{release}.%{arch}\n' \
    $(cut -d' ' -f1 /tmp/lock.adds) | LC_ALL=C sort -u > /tmp/repo.nvras
specs=()
while read -r nevra srpm; do
    nvra=$(sed 's/-[0-9]*:/-/' <<< "$nevra")
    if grep -qxF "$nvra" /tmp/repo.nvras; then
        specs+=("$nevra")
    else
        src=${srpm%.src.rpm}
        srcrel=${src##*-}
        rest=${src%-*}
        srcver=${rest##*-}
        srcname=${rest%-*}
        arch=${nvra##*.}
        echo "locked ${nvra} is no longer on the mirrors; using koji" >&2
        specs+=("https://kojipkgs.fedoraproject.org/packages/${srcname}/${srcver}/${srcrel}/${arch}/${nvra}.rpm")
    fi
done < /tmp/lock.adds
# cosmic-session Recommends cosmic-wallpapers, which the lock deliberately
# omits (ledger 0025); exclude it so the weak dependency cannot pull an
# unlocked copy into the image.
dnf5 -y install --exclude=cosmic-wallpapers "${specs[@]}"

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
# The install above took exact NEVRAs, so this assertion can no longer fail
# from repository drift — it verifies mechanism, not luck: that the closure
# on disk (weak deps, conflicts, scriptlet side effects included) is
# byte-for-byte the committed lockfile. The lock ships in the image so
# `topaz check` can re-verify it on a booted system.
rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH} %{SOURCERPM}\n' \
    | grep -v '^gpg-pubkey' | LC_ALL=C sort > /tmp/rpm-post.list
{
    LC_ALL=C comm -13 /tmp/rpm-pre.list /tmp/rpm-post.list | sed 's/^/+/'
    LC_ALL=C comm -23 /tmp/rpm-pre.list /tmp/rpm-post.list | sed 's/^/-/'
} > /tmp/packages.delta
if ! diff -u /ctx/packages.lock /tmp/packages.delta; then
    echo "Installed package set does not match build_files/packages.lock." >&2
    echo "The locked install and the lock disagree — check gen-lockfile.sh" >&2
    echo "and the transaction output above; 'just lock' rebases the lock." >&2
    exit 1
fi
cp /tmp/packages.delta /usr/share/topaz-os/packages.lock
chmod 644 /usr/share/topaz-os/packages.lock

### Reproducible package installs, epilogue (ledger 0020)
# rpm leaves its sqlite databases in WAL journal mode. A WAL database is
# unreadable without its -wal/-shm sidecars, and those are nondeterministic
# runtime state the image must not ship — but dropping them from a WAL-mode
# database breaks every rpm query on the booted system, where read-only
# /usr prevents recreating them. Checkpoint and convert to DELETE journal
# mode after the last database write: reads (including the check gate's)
# no longer create sidecars, and the database opens fine from read-only
# /usr.
# python3's sqlite3 module, not the sqlite CLI: the base image ships the
# former but not the latter.
for db in /usr/share/rpm/rpmdb.sqlite \
          /usr/lib/sysimage/libdnf5/transaction_history.sqlite; do
    python3 -c '
import sqlite3, sys
con = sqlite3.connect(sys.argv[1], isolation_level=None)
con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
con.execute("PRAGMA journal_mode=DELETE")
con.close()
' "$db"
done

# libxml2's xmlcatalog assembles SGML catalogs in a hash table seeded per
# process, so the docbook-dtds %post (reached through kde-connect's
# kf6-kdoctools dependency) writes the /etc/sgml catalogs in a fresh line
# order on every install. The lines only delegate to disjoint per-DTD
# catalogs, so order carries no meaning — sort each file into a canonical
# order.
grep -q '^CATALOG ' /etc/sgml/catalog
for f in /etc/sgml/catalog /etc/sgml/*.cat; do
    [ -L "$f" ] && continue
    LC_ALL=C sort -o "$f" "$f"
done

### Empty /var (ledger 0024)
# /var is machine state: the image's copy is factory content used once on
# first deploy, then dead weight in every update — and everything the
# build leaves there is a reproducibility hazard (dnf's countme cookies
# roll a random request budget per build, which broke the weekly rebuild
# check). The base image ships /var containing only an empty /var/tmp;
# match it. Scrub the dnf/selinux debris this layer created in /var and
# /run at the end of the same RUN, so none of it is ever committed.
# podman mounts files at arbitrary depth under /run (resolv.conf,
# secrets): skip mounted trees and tolerate busy leaves — mount contents
# never commit to the image, and the check/lint gate in the Containerfile
# is the authority on what actually ships.
for p in /var/* /var/.[!.]* /run/* /run/.[!.]*; do
    [ -e "$p" ] || continue
    findmnt -n "$p" > /dev/null && continue
    rm -rf "$p" 2>/dev/null || true
done
mkdir -p /var/tmp
