---
title: The caustics canvas draws the wallpaper, the idle dim, the polkit prompt and the lock screen
date: 2026-10-26
status: active
paths:
  - /usr/lib/systemd/user/caustics-canvas.service
  - /usr/bin/caustics-canvas
  - /usr/bin/caustics-canvasctl
  - /usr/libexec/topaz/caustics-gpu
  - /etc/pam.d/caustics-lock
---
# The caustics canvas draws the wallpaper, the idle dim, the polkit prompt and the lock screen

Four jobs of the niri (topaz) session that four tools held — swaybg,
chayang, cosmic-osd's polkit agent and swaylock — are now one process:
`caustics-canvas`, a second host over the bar's engine (ledger 0044). It
holds a layer-shell surface on the background layer of every output and
draws the wallpaper with a compute caustic; on command it dims every
output over the windows; it draws the prompt a sink sidecar asks for; and
it takes `ext_session_lock_v1` and draws the lock screen. The canvas is
built, installed and linked as part of the bar's set, so the two hosts
and their sidecars are one contract.

Its sidecars do the talking. `caustics-wallpaper` owns a socket,
`$XDG_RUNTIME_DIR/caustics-canvas.sock`, that scripts drive through
`caustics-canvasctl`: `show <image> [fade <seconds>]` decodes a PNG, JPEG
or JPEG XL and cross-fades to it (the wallpaper schedule, ledger 0048),
`dim <alpha> over <seconds> [--wait]` is the warning before the idle lock
(ledger 0046; `--wait` exits with chayang's codes: 0 at depth, 2
cancelled by input, 1 could not), `status` reports what is shown.
`caustics-polkit` registers with polkitd as this session's agent, has the
canvas prompt for each request and drives `polkit-agent-helper-1`, which
runs PAM; three wrong attempts fail the request. `caustics-lock` hears
logind's `Lock` signal itself (`loginctl lock-session`: the idle timer,
the Super+Alt+L bind), asks the canvas to lock, runs the PAM conversation
as the `caustics-lock` service named on the unit (`/etc/pam.d/caustics-lock`,
shipped: the fingerprint-free `password-auth` stack, so no unlock waits
out pam_fprintd's 5 s with no prompt for it), and takes a fingerprint through fprintd directly, holding
the reader only in windows while someone is at the lock — opened on the
lock, on input and on resume, never while the machine sleeps, closed
after 30 s idle — since a sensor kept verifying for hours disables itself
on heat (`CAUSTICS_LOCK_FINGERPRINT=0` turns it off); nothing but a PAM
success or a matched finger unlocks. It sets logind's `LockedHint`, and a
canvas restarted while locked reads the hint and re-locks before its
first frame. `caustics-canvasctl lock --wait` returns
once the compositor has confirmed the lock: swayidle's before-sleep runs
it, so a suspend is held until the screen is locked.

`caustics-canvas.service` runs the host, gated and wrapped like the bar's
unit (`/usr/libexec/topaz/caustics-gpu <binary>` pins the Vulkan loader to
the integrated GPU on a hybrid laptop). Unlike the bar's, it restarts on
every exit, a refusal and a lost device included: a locked session must
always get its lock client back, and the compositor keeps the session
locked in between. The unit names the full sidecar list in
`CAUSTICS_SIDECARS` — the compiled-in three (wallpaper, reload, glyphs)
plus the polkit agent and the lock, which the canvas starts only when
named, since two agents or two lockers on one session fight.

The tools replaced — swaybg, cosmic-osd's agent as
`topaz-polkit-agent.service`, swaylock as `topaz-locker.service` — stayed
installed and idle as the rescues until the canvas had been lived in,
the lock through a suspend included, and left in ledger 0050. A checkout
of the project installed under `~/.local` brings its own unit of the
same name, which replaces this one; its drop-ins must carry the sidecar
list and the PAM service name, since the checkout's unit sets neither.

Check: the unit carries the wrapper, the gate, `Restart=always`, no
`RestartPreventExitStatus`, no `CAUSTICS_DIR`, exactly this sidecar
list and the PAM service name, and is enabled; `caustics-canvas` and
`caustics-canvasctl` resolve into the installed set and the client runs
(its usage line); the setuid polkit helper, libpam, the `caustics-lock`
PAM file on the fingerprint-free stack and libxkbcommon (the prompt's
keymap, opened at run time) are present. Post-boot: the unit is active and the client reports the
schedule's image; the agent's registration line is in the journal and no
cosmic-osd runs; the lock answers `locked=no` at login; the lock-unlock
suite locks through logind, refuses a wrong password and unlocks on the
right one with the canvas never restarting; the idle-fade suite reads
the dim's progress and cancels it with a key. Suspend with the lock held
is a hardware check.
