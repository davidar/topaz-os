#!/usr/bin/env bash
# Suite: the idle path of the niri (topaz) session (ledgers 0046, 0049).
# The knob file retunes swayidle's stages; the canvas dims the screen
# before the idle lock; a keypress during the dim cancels that lock; an
# undisturbed dim ends in the lock, which a typed password clears. Runs
# the stages in seconds by writing the test user's
# ~/.config/topaz/session.conf, and removes it again at the end.
# topaz-niri only: the idle unit is gated on that session.
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
# The canvas reports its own state (ledger 0049): the wallpaper line
# begins with the dim's, the lock's line says whether the session is
# locked. An unreachable canvas matches nothing, so every probe fails
# closed.
canvas_status() { tssh caustics-canvasctl status 2>/dev/null; }
dimming() { canvas_status | grep -qE '^dim=(dimming|dimmed)'; }
not_dimming() { canvas_status | grep -q '^dim=none'; }
locked() { canvas_status | grep -q '^ok locked=yes'; }
unlocked() { canvas_status | grep -q '^ok locked=no'; }
# canvas_said <since> <text>: the canvas unit's journal since that epoch
# second carries the text (the sidecars' lines included).
canvas_said() { tssh "journalctl --user -u caustics-canvas.service --since @$1 2>/dev/null | grep -q '$2'"; }
brightness() { python3 "$TESTS_DIR/png_mean.py" "$1"; }
# darker <a.png> <b.png>: b is at most 90 % as bright as a. The dim draws
# the wallpaper over the windows, darkened by at most 30 % at full depth,
# so the drop is modest; the capture is taken late in the dim.
darker() { awk -v a="$(brightness "$1")" -v b="$(brightness "$2")" 'BEGIN { exit !(b < a * 0.9) }'; }
# bright <a.png>: a mean above 60/255, enough for the drop to be measurable
# (the night image of the schedule is too dark to tell).
bright() { awk -v a="$(brightness "$1")" 'BEGIN { exit !(a > 60) }'; }
# alike <a.png> <b.png>: within 15 % of each other
alike() { awk -v a="$(brightness "$1")" -v b="$(brightness "$2")" 'BEGIN { exit !(b > a * 0.85 && b < a * 1.15) }'; }
# shot <name>: the capture's path, or nothing where the display mode has
# no hypervisor-side view (the pixel checks are skipped then, not failed).
shot() { local p; p=$(screendump "$RUN_ART/screens/idle-fade-$1.png" 2>/dev/null) && [[ -f "$p" ]] && echo "$p"; }
# A keypress the session ignores but the idle clock and the canvas see.
nudge() { press_key shift; }

check "topaz-idle.service active" units_active topaz-idle.service
check "default stages: a 30 s dim from 270 s, then the lock" \
    argv_has 'timeout 270 caustics-canvasctl dim 1 over 30 --wait || [ $? -ne 2 ] && loginctl lock-session'
check "before-sleep holds on the canvas's lock" argv_has 'before-sleep caustics-canvasctl lock --wait'
check_not "swayidle no longer starts the swaylock unit" argv_has topaz-locker
check "session not locked before the test" unlocked
check "no dim before the test" not_dimming

# Seconds instead of minutes, blank and suspend off. Restarting swayidle
# arms its timers against the compositor's idle clock, which may already
# be past them; the nudge right after restarts the clock from now.
lock=24 warn=12
tssh "mkdir -p $(dirname $knobs) && printf 'TOPAZ_IDLE_LOCK=%s\\nTOPAZ_IDLE_WARN=%s\\nTOPAZ_IDLE_BLANK=0\\nTOPAZ_IDLE_SUSPEND=0\\n' $lock $warn > $knobs &&
      systemctl --user restart topaz-idle.service"
sleep 1
nudge
t1=$(tssh date +%s)
check "knob file retunes the stages: dim $warn s before the lock at $lock s" \
    argv_has "timeout $((lock - warn)) caustics-canvasctl dim 1 over $warn --wait ||"
check_not "blank stage off" argv_has power-off-monitors
check_not "suspend stage off" argv_has "systemctl suspend"

# Cycle one: dim, then cancel it. The dim runs from lock-warn to lock
# after the nudge; capture two thirds of the way in, cancel before it ends.
before=$(shot 0-before)
[[ -n "$before" ]] || echo "no screendump in this display mode; the pixel checks are skipped"
sleep $((lock - warn + warn * 2 / 3 - 1))
check "canvas dimming late in the warning" dimming
check "canvas journal: a dim over $warn s began" canvas_said "$t1" "over $((warn * 1000)) ms"
late=$(shot 1-late-dim)
if [[ -n "$before" && -n "$late" ]]; then
    if bright "$before"; then
        check "screen darker late in the dim than before" darker "$before" "$late"
    else
        echo "screen too dark to measure the dim (mean $(brightness "$before")); the canvas's own state stands"
    fi
fi
nudge
check "dim cancelled by input: canvas reports none within 3 s" wait_for 3 not_dimming
check "canvas journal: the dim was cancelled by a key" canvas_said "$t1" "cancelled by a key"
sleep 2
after=$(shot 2-cancelled)
if [[ -n "$before" && -n "$after" ]]; then
    check "screen back to its brightness after the cancel" alike "$before" "$after"
fi
sleep $((warn + 3))
check "cancelled dim did not lock" unlocked

# Cycle two: the nudge above restarted the clock; leave it alone.
check "undisturbed dim ends in the lock" wait_for $((lock + 10)) locked
check "the lock ended the dim" not_dimming
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
    argv_has 'timeout 270 caustics-canvasctl dim 1 over 30 --wait ||'
check "topaz-idle.service active at the end" units_active topaz-idle.service
check "topaz-locker.service never started (the rescue locker)" locker_idle
check_not "no coredumps during the suite" \
    tssh coredumpctl -q --no-pager list --since "@$t0"

suite_verdict idle-fade
