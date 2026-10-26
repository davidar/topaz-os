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
echo "waiting for the shell to paint..."
wait_session_painted || exit 1

session=$(tssh cat /etc/topaz/test-session 2>/dev/null || echo topaz-niri)
echo "session under test: $session"
sid=$(seat0_session)
check "graphical session on seat0" test -n "$sid"
[[ -n "$sid" ]] || { suite_verdict lock-unlock; exit 1; }
t0=$(tssh date +%s)
check "test password set" set_test_password

# What a working lock looks like from outside (ledger 0049): the canvas's
# lock sidecar hears logind's Lock signal, the canvas takes the session
# lock, and `caustics-canvasctl status` ends with the lock's line —
# locked yes or no, and the failed attempts of the lock held or last held.
# An unreachable canvas matches nothing, so every probe fails closed.
lock_line() { tssh caustics-canvasctl status | grep '^locked='; }
locked() { [[ "$(lock_line)" == "locked=yes"* ]]; }
unlocked() { [[ "$(lock_line)" == "locked=no"* ]]; }
attempts() { lock_line | sed -n 's/.* attempts=//p'; }
# The canvas is resident: it must come through the cycle as the same
# process, with no restart, and the swaylock rescue unit must stay idle.
canvas_state() { tssh systemctl --user show caustics-canvas.service -p ActiveState -p NRestarts -p MainPID; }
before=$(canvas_state)
check "caustics-canvas.service active before the test" contains "$before" ActiveState=active
check "topaz-locker.service idle (the rescue locker)" locker_idle
check "session not locked before the test" unlocked

tssh loginctl lock-session "$sid"
check "locked within 5 s of lock-session" wait_for 5 locked
check "canvas journal: the compositor locked the session" \
    tssh "journalctl --user -u caustics-canvas.service --since @$t0 | grep -q 'the compositor locked the session'"
console_screendump lock-unlock 1-locked

if locked; then
    # The lock screen takes typed characters as the password. A rejected
    # attempt takes PAM's failure delay before a fresh conversation, so
    # give it that long before typing again.
    type_keys wrongpass1 && press_enter
    sleep 4
    check "still locked after a wrong password" locked
    check "the wrong password was counted" test "$(attempts)" = 1
    console_screendump lock-unlock 2-wrong-password

    type_keys "$TEST_PASSWORD" && press_enter
    check "unlocked within 10 s of the right password" wait_for 10 unlocked
    check "canvas journal: the session is unlocked" \
        tssh "journalctl --user -u caustics-canvas.service --since @$t0 | grep -q 'the session is unlocked'"
else
    # Typing a password into an unlocked session would land in whatever
    # has focus; the stages below count as failed, not as passed.
    echo "session never locked; skipping the password stages"
    for stage in "still locked after a wrong password" \
        "the wrong password was counted" \
        "unlocked within 10 s of the right password" \
        "canvas journal: the session is unlocked"; do
        check "$stage (not reached: never locked)" false
    done
fi
after=$(canvas_state)
check "canvas came through the cycle as the same process (no restart)" test "$before" = "$after"
[[ "$before" = "$after" ]] || printf 'canvas before:\n%s\nafter:\n%s\n' "$before" "$after"
check "topaz-locker.service still idle (the rescue locker)" locker_idle
check_not "no coredumps during the suite" \
    tssh coredumpctl -q --no-pager list --since "@$t0"
console_screendump lock-unlock 3-unlocked

suite_verdict lock-unlock
