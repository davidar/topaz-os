#!/usr/bin/env bash
# Suite: the idle path of the niri (topaz) session (ledger 0046). The knob
# file retunes swayidle's stages; the screen fades before the idle lock;
# a keypress during the fade cancels that lock; an undisturbed fade ends
# in the lock, which a typed password clears. Runs the stages in seconds
# by writing the test user's ~/.config/topaz/session.conf, and removes it
# again at the end. topaz-niri only: the idle unit is gated on that
# session.
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
wait_session_painted
t0=$(tssh date +%s)
check "test password set" set_test_password

knobs=/home/tester/.config/topaz/session.conf
idle_argv() { tssh pgrep -u tester -a -x swayidle 2>/dev/null; }
argv_has() { contains "$(idle_argv)" "$1"; }
locker_active() { [[ "$(tssh systemctl --user is-active topaz-locker.service 2>/dev/null)" == active ]]; }
swaylock_running() { tssh pgrep -u tester -x swaylock > /dev/null; }
locked() { locker_active && swaylock_running; }
unlocked() { ! locker_active && ! swaylock_running; }
fading() { tssh pgrep -u tester -x chayang > /dev/null; }
not_fading() { ! fading; }
brightness() { python3 "$TESTS_DIR/png_mean.py" "$1"; }
# darker <a.png> <b.png>: b is at most 70 % as bright as a (a half-black
# overlay halves the mean; the threshold leaves room for the fade's timing)
darker() { awk -v a="$(brightness "$1")" -v b="$(brightness "$2")" 'BEGIN { exit !(a > 20 && b < a * 0.7) }'; }
# alike <a.png> <b.png>: within 15 % of each other
alike() { awk -v a="$(brightness "$1")" -v b="$(brightness "$2")" 'BEGIN { exit !(b > a * 0.85 && b < a * 1.15) }'; }
shot() { screendump "$RUN_ART/screens/idle-fade-$1.png"; }
# A keypress the session ignores but the idle clock and chayang see.
nudge() { press_key shift; }

check "topaz-idle.service active" units_active topaz-idle.service
check "default stages: a 30 s fade from 270 s, then the lock" \
    argv_has 'timeout 270 chayang -d 30 || [ $? -ne 2 ] && loginctl lock-session'
check "session not locked before the test" unlocked

# Seconds instead of minutes, blank and suspend off. Restarting swayidle
# arms its timers against the compositor's idle clock, which may already
# be past them; the nudge right after restarts the clock from now.
lock=24 warn=12
tssh "mkdir -p $(dirname $knobs) && printf 'TOPAZ_IDLE_LOCK=%s\\nTOPAZ_IDLE_WARN=%s\\nTOPAZ_IDLE_BLANK=0\\nTOPAZ_IDLE_SUSPEND=0\\n' $lock $warn > $knobs &&
      systemctl --user restart topaz-idle.service"
sleep 1
nudge
check "knob file retunes the stages: fade $warn s before the lock at $lock s" \
    argv_has "timeout $((lock - warn)) chayang -d $warn ||"
check_not "blank stage off" argv_has power-off-monitors
check_not "suspend stage off" argv_has "systemctl suspend"

# Cycle one: fade, then cancel it. The fade runs from lock-warn to lock
# after the nudge; capture at its midpoint, cancel before it ends.
before=$(shot 0-before) && check "screendump before the fade" test -n "$before"
sleep $((lock - warn + warn / 2 - 2))
check "chayang running mid-fade" fading
mid=$(shot 1-mid-fade) && check "screendump mid-fade" test -n "$mid"
check "screen darker mid-fade than before" darker "$before" "$mid"
nudge
check "fade cancelled by input: chayang gone within 3 s" wait_for 3 not_fading
sleep 2
after=$(shot 2-cancelled) && check "screendump after the cancel" test -n "$after"
check "screen back to its brightness after the cancel" alike "$before" "$after"
sleep $((warn + 3))
check "cancelled fade did not lock" unlocked

# Cycle two: the nudge above restarted the clock; leave it alone.
check "undisturbed fade ends in the lock" wait_for $((lock + 10)) locked
console_screendump idle-fade 3-locked
if locked; then
    type_keys "$TEST_PASSWORD" && press_enter
    check "unlocked within 10 s of the password" wait_for 10 unlocked
else
    check "unlocked within 10 s of the password (not reached: never locked)" false
fi

# Leave the session as found: defaults back, idle clock fresh.
tssh "rm -f $knobs && systemctl --user restart topaz-idle.service"
sleep 1
nudge
check "defaults restored without the knob file" \
    argv_has 'timeout 270 chayang -d 30 ||'
check "topaz-idle.service active at the end" units_active topaz-idle.service
check_not "no coredumps during the suite" \
    tssh coredumpctl -q --no-pager list --since "@$t0"

suite_verdict idle-fade
