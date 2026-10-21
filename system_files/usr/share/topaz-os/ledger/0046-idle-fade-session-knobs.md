---
title: A fade before the idle lock, and the idle timeouts in one knob file
date: 2026-10-21
status: active
paths:
  - /usr/lib/systemd/user/topaz-idle.service
  - /usr/libexec/topaz/idle
  - /usr/share/topaz-os/session.conf
  - /usr/bin/chayang
---

The niri (topaz) session's idle lock (ledger 0041) arrived cold: swayidle
ran `loginctl lock-session` at five minutes with nothing on screen to say
it was coming. cosmic-idle, which it replaced, faded the screen to black
first. swayidle is only a timer; in its world the warning is a separate
tool: chayang (emersion) draws a black overlay on every output and fades
it in over a given number of seconds, exiting 0 when the fade completed,
2 when input cancelled it, and 1 when it could not run. It depends on
libwayland-client alone.

Fedora packages chayang 0.1.0, but that binary cannot run on niri: it
draws its overlay from a wp_single_pixel_buffer_manager_v1 buffer, and
niri registers that global only in its test builds (niri issue 619), so
the packaged chayang exits 1 before drawing anything — the gap the
cosmic-idle fork closes for the COSMIC-on-niri session (ledger 0035). The
image therefore builds chayang itself in the niri-session build stage, at
the upstream commit Fedora packages (`CHAYANG_REF`), with one patch
carried in `build_files/patches/chayang-shm-fallback.patch`: when the
single-pixel-buffer global is absent, the overlay comes from a 1x1
ARGB8888 wl_shm buffer that the viewport scales to the surface exactly as
before. The chayang package itself is not installed, so nothing is
shadowed.

What this entry does:

- **The fade.** The lock stage is now `timeout <lock − warn> "chayang -d
  <warn> || [ $? -ne 2 ] && loginctl lock-session"`: the screen fades for
  the warning period, any input cancels the fade and skips that lock (the
  idle period starts over), and a chayang that cannot run locks anyway —
  a broken fade fails toward a locked screen, never an open one.
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

Check: the patched chayang (its commit recorded in
`/usr/share/topaz-os/niri-session-build`, no chayang package) and the
wrapper present, the unit wired to both, every knob the wrapper reads
documented in the shipped example, and the
wrapper's `--print` output for the defaults (fade at 270 s for 30 s,
blank at 600 s, suspend at 1800 s), with the fade and the suspend
switched off, with every stage off, and with a malformed value. Post-boot:
the VM harness's idle-fade suite retunes the knobs to seconds, measures
the screen darkening mid-fade, cancels one fade with a keypress and lets
the next end in the lock.
