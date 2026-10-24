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

session=$(tssh cat /etc/topaz/test-session 2>/dev/null || echo topaz-niri)
echo "session under test: $session"
sid=$(seat0_session)
check "graphical session on seat0" test -n "$sid"
[[ -n "$sid" ]] || { suite_verdict lock-unlock; exit 1; }
t0=$(tssh date +%s)
check "test password set" set_test_password

# What a working lock looks like from outside (ledger 0041): swayidle
# answers logind's Lock signal by starting topaz-locker.service — swaylock
# in the foreground, which exits once the password is accepted — so the
# unit is active exactly while the screen is locked.
locker_active() { [[ "$(tssh systemctl --user is-active topaz-locker.service 2>/dev/null)" == active ]]; }
swaylock_running() { tssh pgrep -u tester -x swaylock > /dev/null; }
locked() { locker_active && swaylock_running; }
unlocked() { ! locker_active && ! swaylock_running; }
# Before: never started. After: exited cleanly on unlock, no restarts.
locker_state() { tssh systemctl --user show topaz-locker.service -p ActiveState -p Result -p NRestarts; }
locker_idle=$'ActiveState=inactive\nResult=success\nNRestarts=0'
check "topaz-locker.service idle before the test" test "$(locker_state)" = "$locker_idle"
before=$(locker_state)

check "session not locked before the test" unlocked

tssh loginctl lock-session "$sid"
check "locked within 5 s of lock-session" wait_for 5 locked
console_screendump lock-unlock 1-locked

if locked; then
    # The lock screen takes typed characters as the password. A rejected
    # attempt takes PAM's failure delay before the prompt re-arms, so
    # give it that long before typing again.
    type_keys wrongpass1 && press_enter
    sleep 4
    check "still locked after a wrong password" locked
    console_screendump lock-unlock 2-wrong-password

    type_keys "$TEST_PASSWORD" && press_enter
    check "unlocked within 10 s of the right password" wait_for 10 unlocked
else
    # Typing a password into an unlocked session would land in whatever
    # has focus; the stages below count as failed, not as passed.
    echo "session never locked; skipping the password stages"
    for stage in "still locked after a wrong password" \
        "unlocked within 10 s of the right password"; do
        check "$stage (not reached: never locked)" false
    done
fi
after=$(locker_state)
if [[ "$session" = topaz-niri ]]; then
    check "locker unit back to idle (clean exit, no restarts)" test "$after" = "$locker_idle"
    [[ "$after" = "$locker_idle" ]] || printf 'locker unit after:\n%s\n' "$after"
else
    check "locker survived the cycle (same process, no respawn)" test "$before" = "$after"
    [[ "$before" = "$after" ]] || printf 'locker before:\n%s\nafter:\n%s\n' "$before" "$after"
fi
check_not "no coredumps during the suite" \
    tssh coredumpctl -q --no-pager list --since "@$t0"
console_screendump lock-unlock 3-unlocked

suite_verdict lock-unlock
