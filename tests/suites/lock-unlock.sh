#!/usr/bin/env bash
# Suite: lock the graphical session and unlock it at the lock screen, the
# way a user does — logind's lock request, then a password typed at the
# console. Catches a locker that ignores the request (the session stays
# open with nothing on screen to say so), one that lets a wrong password
# through, and one that dies or restarts on the way.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh disable=SC1091
source "$TESTS_DIR/lib.sh"

echo "waiting for ssh..."
wait_ssh 420 || exit 1
echo "waiting for the user session..."
wait_user_graphical 180 || exit 1

session=$(tssh cat /etc/topaz/test-session 2>/dev/null || echo cosmic-niri)
echo "session under test: $session"
sid=$(seat0_session)
check "graphical session on seat0" test -n "$sid"
[[ -n "$sid" ]] || { suite_verdict lock-unlock; exit 1; }
t0=$(tssh date +%s)
check "test password set" set_test_password

# What a working locker leaves behind (cosmic-greeter, ext-session-lock):
# logind's LockedHint on the session and a lockfile in the runtime dir,
# both held for as long as the lock screen is up.
lockfile="/run/user/1000/cosmic-greeter-$sid.lock"
locked() { [[ "$(tssh loginctl show-session "$sid" -p LockedHint --value)" == yes ]]; }
unlocked() { [[ "$(tssh loginctl show-session "$sid" -p LockedHint --value)" == no ]]; }
lockfile_present() { tssh test -e "$lockfile"; }
lockfile_gone() { ! lockfile_present; }

# The locker process: a user unit in the topaz session (ledger 0041),
# a cosmic-session child in COSMIC on niri (0035). Its identity before
# and after the cycle tells "unlocked" apart from "crashed and respawned".
locker_state() {
    if [[ "$session" = topaz-niri ]]; then
        tssh systemctl --user show topaz-locker.service -p MainPID -p ActiveState -p NRestarts
    else
        tssh pgrep -u tester -x cosmic-greeter
    fi
}
before=$(locker_state)
if [[ "$session" = topaz-niri ]]; then
    check "topaz-locker.service active before the test" contains "$before" ActiveState=active
else
    check "cosmic-greeter locker running before the test" test -n "$before"
fi

check "session not locked before the test" unlocked
check_not "no lockfile before the test" lockfile_present

tssh loginctl lock-session "$sid"
check "LockedHint=yes within 5 s of lock-session" wait_for 5 locked
check "locker wrote its lockfile" wait_for 5 lockfile_present
console_screendump lock-unlock 1-locked

if locked; then
    # The lock screen focuses its password field itself. A rejected
    # attempt takes PAM's failure delay before the prompt re-arms, so
    # give it that long before typing again.
    type_keys wrongpass1 && press_enter
    sleep 4
    check "still locked after a wrong password" locked
    check "lockfile kept after a wrong password" lockfile_present
    console_screendump lock-unlock 2-wrong-password

    type_keys "$TEST_PASSWORD" && press_enter
    check "LockedHint=no within 10 s of the right password" wait_for 10 unlocked
    check "lockfile removed on unlock" wait_for 5 lockfile_gone
else
    # Typing a password into an unlocked session would land in whatever
    # has focus; the stages below count as failed, not as passed.
    echo "session never locked; skipping the password stages"
    for stage in "still locked after a wrong password" \
        "lockfile kept after a wrong password" \
        "LockedHint=no within 10 s of the right password" \
        "lockfile removed on unlock"; do
        check "$stage (not reached: never locked)" false
    done
fi
after=$(locker_state)
check "locker survived the cycle (same process, no restarts)" test "$before" = "$after"
[[ "$before" = "$after" ]] || printf 'locker before:\n%s\nafter:\n%s\n' "$before" "$after"
check_not "no coredumps during the suite" \
    tssh coredumpctl -q --no-pager list --since "@$t0"
console_screendump lock-unlock 3-unlocked

suite_verdict lock-unlock
