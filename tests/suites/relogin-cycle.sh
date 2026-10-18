#!/usr/bin/env bash
# Suite: log out of the graphical session and back in through the greeter,
# the way a user does. The autologin only ever exercises the first login of
# a boot; this covers the teardown (ledger 0036: the session's display
# variables must leave the user manager with it) and a real cosmic-greeter
# login, which launches the session from its .desktop entry — a broken
# entry fails here, not at the console of the next person to log in.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh disable=SC1091
source "$TESTS_DIR/lib.sh"

echo "waiting for ssh..."
wait_ssh 420 || exit 1
echo "waiting for the user session..."
wait_user_graphical 180 || exit 1

session=$(tssh cat /etc/topaz/test-session 2>/dev/null || echo cosmic-niri)
entry=$(session_entry_name "$session")
echo "session under test: $session ($entry)"
sid=$(seat0_session)
check "graphical session on seat0" test -n "$sid"
[[ -n "$sid" ]] || { suite_verdict relogin-cycle; exit 1; }
t0=$(tssh date +%s)
check "test password set" set_test_password
# Without a record the greeter offers the stock COSMIC session; this
# makes the login below start the session under test.
check "greeter will preselect \"$entry\"" seed_greeter_session "$entry"

graphical_active() { [[ "$(tssh systemctl --user is-active graphical-session.target)" == active ]]; }
graphical_inactive() { ! graphical_active; }
no_seat0_session() { [[ -z "$(seat0_session)" ]]; }
env_has() { tssh "systemctl --user show-environment | grep -q '^$1='"; }
greeter_up() { tssh 'pgrep -u cosmic-greeter -x cosmic-greeter && pgrep -u cosmic-greeter -x cosmic-comp'; }
greetd_log() { tssh "sudo journalctl -t greetd --since @$t0 --no-pager"; }

# --- logout ---
# niri exits as it answers, so its client reports an EOF; the state checks
# below are the verdict, not this exit code.
# shellcheck disable=SC2016  # $(...) expands in the guest shell
tssh 'NIRI_SOCKET=$(systemctl --user show-environment | sed -n "s/^NIRI_SOCKET=//p") niri msg action quit --skip-confirmation' >/dev/null 2>&1
check "seat0 session $sid ended within 10 s" wait_for 10 no_seat0_session
check "graphical-session.target stopped" wait_for 10 graphical_inactive
# The user manager outlives the session (ssh keeps it up); what it hands
# to the next session's services must not name the old display.
for var in WAYLAND_DISPLAY NIRI_SOCKET DISPLAY; do
    check_not "$var unset in the user manager after logout" env_has "$var"
done
check "greeter up (cosmic-greeter on cosmic-comp)" wait_for 20 greeter_up
# The greeter draws a beat after its process starts.
sleep 3
console_screendump relogin-cycle 1-greeter

# --- login at the greeter ---
# It preselects the seeded user and focuses the password field itself.
type_keys "$TEST_PASSWORD" && press_enter
if wait_for 30 graphical_active; then
    check "graphical-session.target active within 30 s of the login" true
else
    check "graphical-session.target active within 30 s of the login" false
    echo "greetd since the suite started:"
    greetd_log | sed 's/^/    /'
    for stage in "new seat0 session" "session identity" "display variables imported" \
        "session shell running" "shell painted"; do
        check "$stage (not reached: login did not come up)" false
    done
    suite_verdict relogin-cycle
    exit 1
fi

newsid=$(seat0_session)
check "new seat0 session (was $sid, now ${newsid:-none})" \
    test -n "$newsid" -a "$newsid" != "$sid"

# Session identity, as cosmic-greeter sets it from the entry's
# DesktopNames (niri --session then resets XDG_CURRENT_DESKTOP to niri).
check "XDG_CURRENT_DESKTOP=niri session-wide" \
    wait_for 20 tssh 'systemctl --user show-environment | grep -qx XDG_CURRENT_DESKTOP=niri'
if [[ "$session" = topaz-niri ]]; then
    check "XDG_SESSION_DESKTOP=topaz in the user manager (unit gate)" \
        wait_for 20 tssh 'systemctl --user show-environment | grep -qx XDG_SESSION_DESKTOP=topaz'
fi
# The import half of ledger 0036: the new session's display, imported again.
for var in WAYLAND_DISPLAY NIRI_SOCKET DISPLAY; do
    check "$var imported into the user manager" wait_for 20 env_has "$var"
done

if [[ "$session" = topaz-niri ]]; then
    check "session shell units active" \
        wait_for 30 units_active caustics-bar.service topaz-locker.service \
        topaz-idle.service topaz-polkit-agent.service \
        topaz-background.service topaz-clipboard.service
else
    check "cosmic-session running" wait_for 30 tssh pgrep -x cosmic-session
    check "cosmic-panel running" wait_for 30 tssh pgrep -x cosmic-panel
fi
# wait_session_painted picks the shell to wait for from TOPAZ_TEST_SESSION;
# hand it the session read back from the guest.
painted() { TOPAZ_TEST_SESSION="$session" wait_session_painted 60; }
check "shell painted" painted

check "no unexpected failed user units" \
    is_empty tssh "systemctl --user --failed --no-legend --plain | grep -v nvidia"
check_not "no coredumps during the cycle" \
    tssh coredumpctl -q --no-pager list --since "@$t0"
check_not "no stale greeter lockfile" \
    tssh 'ls /run/user/1000/cosmic-greeter-*.lock'
console_screendump relogin-cycle 2-relogged-in

suite_verdict relogin-cycle
