---
title: A dim before the idle lock, and the idle timeouts in one knob file
date: 2026-10-21
status: active
paths:
  - /usr/lib/systemd/user/topaz-idle.service
  - /usr/libexec/topaz/idle
  - /usr/share/topaz-os/session.conf
---

The niri (topaz) session's idle lock (ledger 0041) arrived cold: swayidle
ran `loginctl lock-session` at five minutes with nothing on screen to say
it was coming. cosmic-idle, which it replaced, faded the screen to black
first. swayidle is only a timer; in its world the warning is a separate
tool, run as the lock stage's command.

That tool is the caustics canvas (ledger 0049): `caustics-canvasctl dim 1
over <seconds> --wait` dims every output over the warning period, the
windows dissolving into the wallpaper, and exits 0 when the dim reached
its depth, 2 when input cancelled it (the user is back), and 1 when it
could not be asked for or the canvas went away first. The contract is
chayang's, which held this stage from 2026-10-21 to 2026-10-26: chayang
drew a black overlay, had to be built here with a patch because niri does
not export the single-pixel-buffer protocol it drew from, and left with
its build stage and patch once the canvas could dim.

What this entry does:

- **The dim.** The lock stage is `timeout <lock − warn> "caustics-canvasctl
  dim 1 over <warn> --wait || [ $? -ne 2 ] && loginctl lock-session"`: the
  screen dims for the warning period, any input cancels the dim and skips
  that lock (the idle period starts over), and a canvas that cannot be
  asked locks anyway — a missing warning fails toward a locked screen,
  never an open one. The canvas ends the dim itself when its lock comes.
  `topaz-idle.service` is ordered after `caustics-canvas.service` so the
  canvas is up before the first timer fires.
- **One knob file.** `topaz-idle.service` reads `~/.config/topaz/
  session.conf` as an optional `EnvironmentFile` and runs
  `/usr/libexec/topaz/idle`, which assembles swayidle's stages from
  `TOPAZ_IDLE_LOCK`, `TOPAZ_IDLE_WARN`, `TOPAZ_IDLE_BLANK` and
  `TOPAZ_IDLE_SUSPEND` (defaults 300, 30, 600, 1800 seconds; 0 switches a
  stage off; a malformed value is reported to the journal and the default
  used). Retuning or disabling a stage is one line in one file instead of
  a copied `ExecStart` in a drop-in, and `/usr/share/topaz-os/session.conf`
  documents every knob with its default. The file is the intended home
  for any further per-session knob a topaz unit grows; drop-ins keep
  working for anything else.

Check: no chayang in the image or its build record, the wrapper present,
the unit wired to it and ordered after the canvas, every knob the wrapper
reads documented in the shipped example, and the wrapper's `--print`
output for the defaults (dim at 270 s for 30 s, blank at 600 s, suspend
at 1800 s), with the dim and the suspend switched off, with every stage
off, and with a malformed value. Post-boot: the VM harness's idle-fade
suite retunes the knobs to seconds, reads the canvas's dim state and
measures the screen darkening late in the dim, cancels one dim with a
keypress and lets the next end in the lock.
