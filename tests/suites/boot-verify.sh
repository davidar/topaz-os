#!/usr/bin/env bash
# Suite: a healthy first boot into the autologin COSMIC-on-niri session.
# Machine-checks the assertable half of the post-boot checklist that has
# so far been verified by hand after every reboot.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh disable=SC1091
source "$TESTS_DIR/lib.sh"

echo "waiting for ssh..."
wait_ssh 420 || exit 1
echo "waiting for the user session..."
wait_user_graphical 180 || exit 1

# Which session the test image autologs into (tests/Containerfile.test,
# TOPAZ_TEST_SESSION): topaz-niri (ledger 0041) is the only one.
session=$(tssh cat /etc/topaz/test-session 2>/dev/null || echo topaz-niri)
echo "session under test: $session"
# niri --session resets XDG_CURRENT_DESKTOP to niri; the topaz session is
# told apart by XDG_SESSION_DESKTOP (the entry's DesktopNames).
expected_desktop=niri

# Session identity: the autologin wrapper must have preserved the values
# a real tuigreet login sets from the session's .desktop file.
check "XDG_CURRENT_DESKTOP=$expected_desktop session-wide" \
    tssh "systemctl --user show-environment | grep -qx XDG_CURRENT_DESKTOP=$expected_desktop"
check "XDG_SESSION_DESKTOP=topaz in the user manager (unit gate)" \
    tssh 'systemctl --user show-environment | grep -q ^XDG_SESSION_DESKTOP=topaz'

# The session-env import (ledger 0036): without it portals have no display.
check "WAYLAND_DISPLAY imported into the user manager" \
    tssh 'systemctl --user show-environment | grep -q ^WAYLAND_DISPLAY='
check "NIRI_SOCKET imported into the user manager" \
    tssh 'systemctl --user show-environment | grep -q ^NIRI_SOCKET='
check "DISPLAY imported (xwayland-satellite up)" \
    tssh 'systemctl --user show-environment | grep -q ^DISPLAY='

# Failed units expected only in the VM: the guest has none of the
# laptop's NVIDIA hardware and QEMU's CPU exposes no MCE banks.
vm_allowed='^(nvidia-cdi-refresh\.(path|service)|nvidia-persistenced\.service|mcelog\.service) '
check "no unexpected failed system units" \
    is_empty tssh "systemctl --failed --no-legend --plain | grep -vE '$vm_allowed'"
check "no unexpected failed user units" \
    is_empty tssh "systemctl --user --failed --no-legend --plain | grep -v nvidia"
check_not "no coredumps this boot" tssh coredumpctl -q --no-pager list

# The compositor and shell are up and answering.
# shellcheck disable=SC2016  # $(...) expands in the guest shell, deliberately
check "niri answers IPC" \
    tssh 'NIRI_SOCKET=$(systemctl --user show-environment | sed -n "s/^NIRI_SOCKET=//p") niri msg version'
check "niri.service active (niri's own session integration)" \
    tssh systemctl --user is-active niri.service
check "session shell units active" \
    units_active caustics-bar.service \
        topaz-idle.service topaz-polkit-agent.service \
        topaz-background.service topaz-clipboard.service
# The locker unit is swayidle's to start on a lock; at login it must
# be neither running nor failed.
check "topaz-locker.service idle until a lock" locker_idle
check "caustics bar runs from the installed set" \
    tssh 'readlink -f /proc/$(pgrep -x caustics-bar)/exe | grep -q ^/usr/lib/caustics-bar/'
check "notification daemon on the bus is caustics-notify" \
    tssh 'pid=$(busctl --user status org.freedesktop.Notifications | sed -n "s/^PID=//p"); [ "$(cat /proc/$pid/comm)" = caustics-notify ]'
check_not "cosmic-panel absent" tssh pgrep -x cosmic-panel
check_not "cosmic-notifications absent" tssh pgrep -x cosmic-notifications
check_not "wob absent (the bar draws the OSD)" tssh command -v wob
check_not "cosmic-session absent" tssh pgrep -x cosmic-session

# Portal wiring (ledger 0039): niri registers the Mutter ScreenCast API,
# portal-gnome consumes it; gtk backs FileChooser; the Settings route
# answers end to end.
check "niri owns org.gnome.Mutter.ScreenCast" \
    tssh 'busctl --user status org.gnome.Mutter.ScreenCast'
# The frontend is D-Bus-activated on first use; nothing in the topaz
# session asks for a portal before an app does, so wake it explicitly.
tssh 'busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping >/dev/null 2>&1; sleep 2' || true
check "xdg-desktop-portal frontend on the bus" \
    tssh 'busctl --user status org.freedesktop.portal.Desktop'
check "gtk portal backend on the bus" \
    tssh 'busctl --user status org.freedesktop.impl.portal.desktop.gtk'
check "portal-gnome exports ScreenCast" \
    tssh 'busctl --user introspect org.freedesktop.impl.portal.desktop.gnome /org/freedesktop/portal/desktop | grep -q impl.portal.ScreenCast'
check "frontend serves FileChooser" \
    tssh 'busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep -q portal.FileChooser'
check "Settings portal answers color-scheme" \
    tssh 'busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme'

# topaz check as root: every claim must hold in the booted test image
# (its layer adds the autologin, sshd and sudo, deviating from nothing
# the check asserts).
# (tc_fails, not fails: that name is the suite's failure counter.)
tc_out="$(tssh sudo topaz check 2>/dev/null || true)"
tc_fails="$(printf '%s\n' "$tc_out" | grep '^\[FAIL\]' || true)"
check "topaz check ran" test -n "$tc_out"
check "topaz check: no failures" test -z "$tc_fails"
[[ -n "$tc_fails" ]] && printf '%s\n' "$tc_fails"

# The screendump is evidence, not decoration: a failed or invalid
# capture fails the suite instead of shipping a broken artifact.
wait_session_painted 60
check "screendump: boot-verify.png" screendump "$ART/screens/boot-verify.png"

suite_verdict boot-verify
