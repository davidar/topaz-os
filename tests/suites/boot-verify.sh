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

# Session identity: the autologin wrapper must have preserved the values
# a real cosmic-greeter login sets from the session's .desktop file.
check "XDG_CURRENT_DESKTOP=niri session-wide" \
    tssh 'systemctl --user show-environment | grep -qx XDG_CURRENT_DESKTOP=niri'

# The session-env import (ledger 0036): without it portals have no display.
check "WAYLAND_DISPLAY imported into the user manager" \
    tssh 'systemctl --user show-environment | grep -q ^WAYLAND_DISPLAY='
check "NIRI_SOCKET imported into the user manager" \
    tssh 'systemctl --user show-environment | grep -q ^NIRI_SOCKET='
check "DISPLAY imported (xwayland-satellite up)" \
    tssh 'systemctl --user show-environment | grep -q ^DISPLAY='

# Failed units expected only in the VM: the guest has none of the
# laptop's NVIDIA hardware and QEMU's CPU exposes no MCE banks.
vm_allowed='^(nvidia-cdi-refresh\.(path|service)|mcelog\.service) '
check "no unexpected failed system units" \
    is_empty tssh "systemctl --failed --no-legend --plain | grep -vE '$vm_allowed'"
check "no unexpected failed user units" \
    is_empty tssh "systemctl --user --failed --no-legend --plain | grep -v nvidia"
check_not "no coredumps this boot" tssh coredumpctl -q --no-pager list

# The compositor and shell are up and answering.
# shellcheck disable=SC2016  # $(...) expands in the guest shell, deliberately
check "niri answers IPC" \
    tssh 'NIRI_SOCKET=$(systemctl --user show-environment | sed -n "s/^NIRI_SOCKET=//p") niri msg version'
check "cosmic-session running" tssh pgrep -x cosmic-session
check "cosmic-panel running" tssh pgrep -x cosmic-panel

# Portal wiring (ledger 0039): niri registers the Mutter ScreenCast API,
# portal-gnome consumes it; gtk backs FileChooser; the Settings route
# answers end to end.
check "niri owns org.gnome.Mutter.ScreenCast" \
    tssh 'busctl --user status org.gnome.Mutter.ScreenCast'
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

# Lock state: a fresh boot must not carry a greeter lockfile.
check_not "no stale greeter lockfile" \
    tssh 'ls /run/user/1000/cosmic-greeter-*.lock'

# topaz check as root. The only expected failure is the enforced-GDM
# claim — the test image flips the DM to cosmic-greeter, which is also
# the greetd-trial state on hardware. Its presence proves the check ran.
tc_out="$(tssh sudo topaz check 2>/dev/null || true)"
unexpected="$(printf '%s\n' "$tc_out" | grep '^\[FAIL\]' | grep -vF 'GDM remains the display manager' || true)"
check "topaz check: no unexpected failures" test -z "$unexpected"
check "topaz check: GDM flip is the one expected failure" \
    contains "$tc_out" '[FAIL] GDM remains the display manager'
[[ -n "$unexpected" ]] && printf '%s\n' "$unexpected"

shot="$(screendump "$ART/screens/boot-verify.png" || true)"
[[ -n "$shot" ]] && echo "screendump: $shot"

suite_verdict boot-verify
