#!/bin/bash

# Configuration layer: topaz system files plus every patch and enablement
# applied on top of the installed package set. This is the layer that
# changes most often, and it is kilobytes — keeping it last means a config
# or check edit re-ships almost nothing.

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
# arming wedges that arming forever, freezing COSMIC at the first idle.
# The daemon reaches /dev/i2c-*
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
# image, invalidating an otherwise-unchanged layer on every rebuild;
# in a container build there is no prior state to restore.
authselect select custom/local-custom \
    with-fingerprint with-silent-lastlog with-mdns4 --force --nobackup

### supergfxd (GPU mode switching)
# Preset shipped in system_files; enable in the built image as well so the
# guarantee does not depend on first-boot preset application.
systemctl enable supergfxd.service

### topaz-pull timer
# Same preset-plus-enable pattern: stage updates via topaz pull daily,
# half an hour before uupd's bootc step (which then no-ops).
systemctl enable topaz-pull.timer

### Disk swapfile behind zswap
# The image ships no zram device; swap is zswap over a swapfile that
# topaz-swapfile.service creates on first boot. Preset plus enable, as
# above, so a disk without preset application still gets its swap.
systemctl enable var-swap-swapfile.swap

### Boot log on the console
# The kernel arguments in kargs.d/20-topaz-console.toml show the boot as
# text. This unit lowers the kernel's console level again once the
# greeter takes the screen. Preset plus enable, as above. Guards: the
# base still boots behind Plymouth, whose units honour the argument that
# turns it off, and the font the arguments name is installed.
grep -q '^ConditionKernelCommandLine=!plymouth.enable=0$' \
    /usr/lib/systemd/system/plymouth-start.service
test -f /usr/lib/kbd/consolefonts/ter-v24n.psf.gz
systemctl enable topaz-console-loglevel.service

### Firmware framebuffer for the early boot log
# The base's NVIDIA arguments keep simpledrm from loading, which leaves
# no console until the GPU driver is up. Drop that one argument (bootc
# removes it from installed machines too); the reason is in `topaz
# check`. Guard: the base's file still ends with it.
grep -q ', "initcall_blacklist=simpledrm_platform_driver_init"\]$' \
    /usr/lib/bootc/kargs.d/00-nvidia.toml
sed -i 's/, "initcall_blacklist=simpledrm_platform_driver_init"\]$/]/' \
    /usr/lib/bootc/kargs.d/00-nvidia.toml

### KDE Connect firewall ports
# KDE Connect itself runs from a distrobox (topaz-home's kdeconnect
# recipe), but the container shares the
# host network namespace, so the host firewall must still pass its
# discovery and transfer ports. The service definition (TCP/UDP
# 1714-1764) ships with firewalld; open it in the default zone.
firewall-offline-cmd --zone=FedoraWorkstation --add-service=kdeconnect

### Partial image pulls
# CI publishes the image as zstd:chunked (see build.yml); flip the
# containers-storage default so podman pulls fetch only the files not
# already present in local storage. `topaz pull` stages updates through
# podman, so this is the client half of delta updates. Patch the shipped
# default rather than adding an /etc/containers/storage.conf override —
# an override copy would shadow every future base change to the file.
grep -q '^# enable_partial_images = "false"$' /usr/share/containers/storage.conf
sed -i 's|^# enable_partial_images = "false"$|enable_partial_images = "true"|' \
    /usr/share/containers/storage.conf

### niri session portals: gtk first; ScreenCast, Screenshot and Settings
### on gnome
# The frontend routes by what a backend's .portal file DECLARES, and
# portal-gnome declares eighteen interfaces while exporting only the few
# it can serve off GNOME — so upstream's gnome-first default sends
# FileChooser (and everything else both files declare) into "no such
# interface" with no fallback. Put gtk, which exports what it declares,
# first, so FileChooser and the other dialogs are portal-gtk's; route
# the three portal-gnome does serve here explicitly, since each is the
# load-bearing route and should not be an accident of list order:
# ScreenCast and Screenshot consume the Mutter ScreenCast and Shell
# Screenshot D-Bus APIs `niri --session` registers, and Settings answers
# color-scheme and accent-color from gsettings, the one theme switch
# this session has now that no COSMIC shell writes cosmic-config.
# Guard: fail the build if upstream's file gains its own
# preferences or changes shape.
grep -q '^default=gnome;gtk;$' /usr/share/xdg-desktop-portal/niri-portals.conf
! grep -qE 'portal\.(Settings|ScreenCast|Screenshot|FileChooser)' /usr/share/xdg-desktop-portal/niri-portals.conf
sed -i 's/^default=gnome;gtk;$/default=gtk;gnome;/' \
    /usr/share/xdg-desktop-portal/niri-portals.conf
printf '%s\n' \
    'org.freedesktop.impl.portal.FileChooser=gtk;' \
    'org.freedesktop.impl.portal.ScreenCast=gnome;' \
    'org.freedesktop.impl.portal.Screenshot=gnome;' \
    'org.freedesktop.impl.portal.Settings=gnome;' \
    >> /usr/share/xdg-desktop-portal/niri-portals.conf

### niri (topaz) session
# The session's shell is systemd user units wanted by
# graphical-session.target (niri's own session integration starts it),
# each gated on XDG_SESSION_DESKTOP=topaz so the COSMIC session is
# untouched. Portals: niri --session resets XDG_CURRENT_DESKTOP to niri,
# so the session shares niri-portals.conf above. Preset shipped in
# system_files; enabled here as well.
systemctl --global enable \
    caustics-bar.service caustics-canvas.service topaz-idle.service \
    topaz-background.service topaz-clipboard.service

### The lock screen's PAM stack
# The canvas's lock sidecar authenticates through the shipped
# /etc/pam.d/caustics-lock, which includes password-auth: the system-auth
# stack without pam_fprintd, whose 5 s timeout every unlock would
# otherwise wait out with no fingerprint prompt on screen (the lock takes
# fingerprints through fprintd itself). Guards: the shipped file is in
# place and names that stack, and the base's password-auth still carries
# the password module and no fingerprint one.
grep -qE '^auth\s+include\s+password-auth$' /etc/pam.d/caustics-lock
! test -e /etc/pam.d/swaylock
grep -qE '^auth\s+sufficient\s+pam_unix\.so' /etc/pam.d/password-auth
if grep -q pam_fprintd /etc/pam.d/password-auth; then
    echo "password-auth now carries pam_fprintd; the lock's stack needs another base" >&2
    exit 1
fi

### greetd with tuigreet as the display manager
# The base image logs in through GDM. greetd (a dependency of tuigreet)
# runs tuigreet on VT 1 instead: a terminal greeter with no compositor or
# toolkit of its own, so the login path shares nothing with the sessions
# it starts. Both units carry Alias=display-manager.service, so GDM is
# disabled first to free the alias. Guards: the base still logs in
# through GDM (a change there deserves a look), the shipped greetd config
# names tuigreet, the binary exists, and the alias ends up on greetd.
[ "$(readlink /etc/systemd/system/display-manager.service)" = /usr/lib/systemd/system/gdm.service ]
grep -q '^command = "tuigreet ' /etc/greetd/config.toml
test -x /usr/bin/tuigreet
systemctl disable gdm.service
systemctl enable greetd.service
[ "$(readlink /etc/systemd/system/display-manager.service)" = /usr/lib/systemd/system/greetd.service ]

### greetd's PAM stack: password only
# Fedora's file substacks system-auth, whose pam_fprintd (5 s timeout)
# runs ahead of the password module; tuigreet runs the conversation in
# order, so every login would wait those 5 s before the password prompt,
# for a fingerprint that cannot unlock the keyring anyway. password-auth
# is the same stack without the fingerprint module (as for the lock
# above). The session half keeps system-auth and the keyring module, so
# the typed password unlocks the keyring. Guards as for the lock.
grep -qE '^auth\s+substack\s+system-auth$' /usr/lib/pam.d/greetd
sed -i -E 's/^(auth\s+substack\s+)system-auth$/\1password-auth/' /usr/lib/pam.d/greetd
grep -qE '^auth\s+substack\s+password-auth$' /usr/lib/pam.d/greetd
if grep -qE '^auth\s+.*system-auth' /usr/lib/pam.d/greetd; then
    echo "greetd's auth stack still reaches system-auth (pam_fprintd)" >&2
    exit 1
fi

### Secret Service in every session
# The base starts oo7-daemon only from gnome-session-services.target and
# ships no D-Bus activation file for org.freedesktop.secrets, so outside
# GNOME nothing starts it: pam_oo7 hands the login password to a helper
# that waits two minutes for a daemon and gives up, and no application
# has a keyring. Enable the unit for every user (its own install target,
# default.target). Guards: the unit still installs there, greetd's stack
# still carries the PAM module that feeds it, and nothing has started
# activating the name by itself (then this enable is redundant).
grep -q '^WantedBy=default.target$' /usr/lib/systemd/user/oo7-daemon.service
grep -qE '^-?session\s+optional\s+pam_oo7\.so\s+auto_start$' /usr/lib/pam.d/greetd
if grep -rqs '^Name=org.freedesktop.secrets$' /usr/share/dbus-1/services/; then
    echo "the base now D-Bus-activates org.freedesktop.secrets; the oo7-daemon enable may be redundant" >&2
    exit 1
fi
systemctl --global enable oo7-daemon.service
test -L /etc/systemd/user/default.target.wants/oo7-daemon.service

### Empty /var
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
