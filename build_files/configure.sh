#!/bin/bash

# Configuration layer: topaz system files plus every patch and enablement
# applied on top of the installed package set. This is the layer that
# changes most often, and it is kilobytes — keeping it last means a config
# or ledger edit re-ships almost nothing.

set -ouex pipefail

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

### topaz-pull timer (ledger 0032)
# Same preset-plus-enable pattern: stage updates via topaz pull daily,
# half an hour before uupd's bootc step (which then no-ops).
systemctl enable topaz-pull.timer

### KDE Connect firewall ports (ledger 0030)
# KDE Connect itself runs from a distrobox (topaz-home's kdeconnect
# recipe; ledger 0026 records the eviction), but the container shares the
# host network namespace, so the host firewall must still pass its
# discovery and transfer ports. The service definition (TCP/UDP
# 1714-1764) ships with firewalld; open it in the default zone.
firewall-offline-cmd --zone=FedoraWorkstation --add-service=kdeconnect

### Partial image pulls (ledger 0031)
# CI publishes the image as zstd:chunked (see build.yml); flip the
# containers-storage default so podman pulls fetch only the files not
# already present in local storage. `topaz pull` stages updates through
# podman, so this is the client half of delta updates. Patch the shipped
# default rather than adding an /etc/containers/storage.conf override —
# an override copy would shadow every future base change to the file.
grep -q '^# enable_partial_images = "false"$' /usr/share/containers/storage.conf
sed -i 's|^# enable_partial_images = "false"$|enable_partial_images = "true"|' \
    /usr/share/containers/storage.conf

### COSMIC on niri session launcher (ledger 0035)
# The alternative session wants everything the COSMIC session's startup
# script does — the failed-unit reset, the login-shell environment, the
# Qt theme and keyring plumbing — and differs only in which compositor
# cosmic-session is told to launch (it takes that from its argument
# alone; there is no environment variable for it). Derive the launcher
# from the packaged script instead of shipping a second copy, so upstream
# changes to the session environment reach both sessions. The session
# file sets XDG_CURRENT_DESKTOP=niri, which the script only defaults.
# The compositor is launched through /usr/libexec/topaz/niri-journal,
# which sends niri's log to the journal (cosmic-session discards the
# compositor's stderr), and a directory of session-only shims is put on
# PATH ahead of the packaged binaries (the panel's Workspaces button is
# routed to niri's own overview). Guards: fail the build if either exec
# line or the run marker moves or changes shape.
[ "$(grep -c '/usr/bin/cosmic-session$' /usr/bin/start-cosmic)" = 2 ]
[ "$(grep -c '^# Run cosmic-session$' /usr/bin/start-cosmic)" = 1 ]
sed -e 's|/usr/bin/cosmic-session$|/usr/bin/cosmic-session /usr/libexec/topaz/niri-journal|' \
    -e 's|^# Run cosmic-session$|export PATH=/usr/libexec/topaz/niri-session:$PATH\n\n&|' \
    /usr/bin/start-cosmic > /usr/bin/start-cosmic-niri
chmod 0755 /usr/bin/start-cosmic-niri
test -x /usr/libexec/topaz/niri-journal
test -x /usr/libexec/topaz/niri-session/cosmic-workspaces

### Session teardown stops graphical-session.target (ledger 0036)
# start-cosmic execs cosmic-session and never stops graphical-session.target
# when the session ends: xdg-desktop-portal's Requisite= on that target
# pins it (it is StopWhenUnneeded), so a logout leaves the portal daemon —
# and everything else PartOf= the target — alive with the dead session's
# environment, and the next login of either session inherits a portal
# wired to the previous compositor. Run cosmic-session as a child instead
# and, once it exits, force the target down through a Conflicts= target
# and unset the session variables: the teardown niri-session and
# gnome-session already perform. Both launchers, so switching between the
# sessions is clean in either direction.
# Guard: fail the build if the exec lines move or change shape.
for launcher in /usr/bin/start-cosmic /usr/bin/start-cosmic-niri; do
    [ "$(grep -cE '^    exec (/usr/bin/dbus-run-session -- )?/usr/bin/cosmic-session( /usr/libexec/topaz/niri-journal)?$' \
        "$launcher")" = 2 ]
    sed -i -E 's#^    exec ((/usr/bin/dbus-run-session -- )?/usr/bin/cosmic-session( /usr/libexec/topaz/niri-journal)?)$#    \1 || rc=$?#' \
        "$launcher"
    cat >> "$launcher" <<'TEARDOWN'

# topaz-os (ledger 0036): tear the graphical session down once
# cosmic-session exits, so nothing PartOf= graphical-session.target
# outlives the session or leaks its environment into the next one.
if command -v systemctl >/dev/null; then
    systemctl --user start --job-mode=replace-irreversibly \
        topaz-session-shutdown.target || :
    systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET \
        XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP || :
fi
exit "${rc:-0}"
TEARDOWN
    [ "$(grep -c ' || rc=\$?$' "$launcher")" = 2 ]
    ! grep -qE '^ *exec .*cosmic-session' "$launcher"
    bash -n "$launcher"
done

### niri session portals: gtk first, ScreenCast on gnome, Settings from
### COSMIC (ledger 0039)
# The frontend routes by what a backend's .portal file DECLARES, and
# portal-gnome declares fourteen interfaces while exporting only Settings
# when not on GNOME — so upstream's gnome-first default sends FileChooser
# (and everything else both files declare) into "no such interface" with
# no fallback. Put gtk, which exports what it declares, first; route
# ScreenCast explicitly to gnome (its backend consumes the Mutter API the
# baked niri config registers); route Settings to portal-cosmic, which
# reads the session's theme from cosmic-config directly and runs fine
# under niri — portal-gnome's gsettings-backed Settings would miss a
# COSMIC dark/light toggle. FileChooser also goes to portal-cosmic: its
# dialog (COSMIC Files in dialog mode) is an ordinary window that works
# under niri and matches the shell, unlike its capture-bound
# ScreenCast/Screenshot. Guard: fail the build if upstream's file gains
# its own preferences or changes shape.
grep -q '^default=gnome;gtk;$' /usr/share/xdg-desktop-portal/niri-portals.conf
! grep -qE 'portal\.(Settings|ScreenCast|FileChooser)' /usr/share/xdg-desktop-portal/niri-portals.conf
sed -i 's/^default=gnome;gtk;$/default=gtk;gnome;/' \
    /usr/share/xdg-desktop-portal/niri-portals.conf
printf '%s\n' \
    'org.freedesktop.impl.portal.FileChooser=cosmic;gtk;' \
    'org.freedesktop.impl.portal.ScreenCast=gnome;' \
    'org.freedesktop.impl.portal.Settings=cosmic;gnome;' \
    >> /usr/share/xdg-desktop-portal/niri-portals.conf

### Empty /var (ledger 0024)
# The package layer already scrubbed its own debris; assert the tmpfiles.d
# fragment that replaces the one functional /var item (greetd's
# xdg-desktop-portal mask, recreated at boot) is among the shipped files,
# and re-scrub as insurance against this layer's own tooling — the
# check/lint gate in the Containerfile is the authority on what ships.
grep -q 'xdg-desktop-portal.service - - - - /dev/null' \
    /usr/lib/tmpfiles.d/topaz-greetd-portal-mask.conf
for p in /var/* /var/.[!.]* /run/* /run/.[!.]*; do
    [ -e "$p" ] || continue
    findmnt -n "$p" > /dev/null && continue
    rm -rf "$p" 2>/dev/null || true
done
mkdir -p /var/tmp
