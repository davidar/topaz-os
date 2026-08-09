#!/bin/bash

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

# Copy system_files/ from the repo into the image
cp -avf "/ctx/system_files"/. /

### Image identity (os-release)
# GRUB titles boot entries with os-release PRETTY_NAME, so without this the
# booted topaz-os deployment and its Bluefin rollback render as identical
# menu lines. Rebrand NAME and PRETTY_NAME only; ID, ID_LIKE, VARIANT_ID,
# IMAGE_ID and the rest stay Bluefin's so tooling keyed on them still works.
# Guard: fail loudly if the base image reshapes the fields we rewrite
grep -q '^NAME="Bluefin"' /usr/lib/os-release
grep -q '^PRETTY_NAME="Bluefin ' /usr/lib/os-release
base_version=$(. /usr/lib/os-release && echo "$IMAGE_VERSION")
sed -i \
    -e 's/^NAME=.*/NAME="topaz-os"/' \
    -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"topaz-os (Bluefin $base_version)\"/" \
    /usr/lib/os-release

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
dnf5 -y install "${specs[@]}"

dnf5 -y copr disable antiderivative/libfprint-tod-goodix-0.0.9

# COSMIC installs alongside the base image's GNOME; selectable from the GDM
# session picker. cosmic-greeter comes along as a hard dependency of
# cosmic-session but is not enabled: GDM remains the display manager
# (verified by `topaz check`).

### Forked cosmic-comp (config-driven workspace gestures)
# The Fedora binary is replaced with a build of the topaz fork
# (github.com/davidar/cosmic-comp, compiled in the Containerfile's
# comp-build stage at a pinned commit): workspace-swipe finger count, swipe
# physics, and rubber-band edge bounce become hot-reloadable config, pending
# upstream (pop-os/cosmic-epoch#54). Ledger 0015. Guard: fail loudly when
# Fedora bumps cosmic-comp, so the fork gets rebased rather than silently
# shadowing a newer base version.
fork_base_version=1.5.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-comp)
if [ "$packaged_version" != "$fork_base_version" ]; then
    echo "cosmic-comp is now $packaged_version but the fork is based on $fork_base_version" >&2
    echo "Rebase github.com/davidar/cosmic-comp (branch topaz) and update COSMIC_COMP_REF" >&2
    exit 1
fi
install -m0755 /comp/cosmic-comp /usr/bin/cosmic-comp
{ cat /comp/fork-info; echo "base=$fork_base_version"; } \
    > /usr/share/topaz-os/cosmic-comp-fork

### No passwordless DDC/CI access to GPU i2c buses
# cosmic-settings-daemon's brightness module blindly DDC-probes every GPU
# i2c bus (including disconnected DP ports) about a second after the
# compositor starts. On this hardware (amdgpu DCN 3.1.4, PSR eDP), a raw
# AUX transaction to a disconnected port before the panel's first PSR
# arming wedges that arming forever, freezing COSMIC at the first idle —
# ledger 0013 has the full investigation. The daemon reaches /dev/i2c-*
# through seat-user ACLs granted by udev `uaccess` rules; two base-image
# packages ship one. Closing both (and the wider unprivileged-DDC surface)
# leaves `sudo ddcutil` and OpenRGB's non-i2c device access working. Drop
# once the daemon probes politely. Guards: fail the build if either rule
# moves or changes shape upstream; `topaz check` additionally sweeps the
# whole rules directory for any i2c uaccess grant.
grep -q 'SUBSYSTEM=="i2c-dev".*TAG+="uaccess"' \
    /usr/lib/udev/rules.d/60-ddcutil-i2c.rules
rm /usr/lib/udev/rules.d/60-ddcutil-i2c.rules
grep -q '^KERNEL=="i2c-\[0-99\]\*", TAG+="uaccess"$' \
    /usr/lib/udev/rules.d/60-openrgb.rules
sed -i '/^KERNEL=="i2c-\[0-99\]\*", TAG+="uaccess"$/d' \
    /usr/lib/udev/rules.d/60-openrgb.rules

### earlyoom (installed via the lockfile above)
# Intervenes on memory pressure earlier than systemd-oomd; configuration in
# system_files/etc/default/earlyoom adds a swap threshold to catch thrashing.
systemctl enable earlyoom.service

### Fingerprint-friendly PAM stack (authselect)
# The default fingerprint PAM flow blocks password entry until fprintd times
# out (30s). Generate a custom profile from the base `local` profile: every
# file is a symlink back to the base, so upstream profile changes flow through
# automatically, except system-auth, which is copied and patched to set
# timeout=5 so the password prompt appears after 5s if the reader is unused.
authselect create-profile local-custom --base-on local \
    --symlink-meta --symlink-nsswitch --symlink-dconf --symlink-pam
rm /etc/authselect/custom/local-custom/system-auth
cp /usr/share/authselect/default/local/system-auth \
    /etc/authselect/custom/local-custom/system-auth
# Guard: fail the build if upstream reshaped the pam_fprintd line
grep -Eq 'pam_fprintd\.so\s+\{include if "with-fingerprint"\}' \
    /etc/authselect/custom/local-custom/system-auth
sed -i 's/pam_fprintd\.so/pam_fprintd.so timeout=5/' \
    /etc/authselect/custom/local-custom/system-auth
# --nobackup: the automatic backup bakes a timestamped directory into the
# image, invalidating an otherwise-unchanged layer on every rebuild
# (ledger 0020); in a container build there is no prior state to restore.
authselect select custom/local-custom \
    with-fingerprint with-silent-lastlog with-mdns4 --force --nobackup

### supergfxd (GPU mode switching)
# Preset shipped in system_files; enable in the built image as well so the
# guarantee does not depend on first-boot preset application.
systemctl enable supergfxd.service

### KDE Connect (installed via the lockfile above; phone integration + SMS)
# Chosen over Valent/Flathub alternatives: Fedora's package ships the full
# app set (kdeconnect-sms was the deciding feature), and Flathub carries
# neither KDE Connect nor Valent. The firewall service (ports 1714-1764)
# ships with firewalld; open it in the default zone so pairing works out of
# the box.
firewall-offline-cmd --zone=FedoraWorkstation --add-service=kdeconnect

### nethogs (installed via the lockfile above; ledger 0023)
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
