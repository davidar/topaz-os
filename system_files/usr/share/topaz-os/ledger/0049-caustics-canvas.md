---
title: The caustics canvas draws the wallpaper
date: 2026-10-26
status: active
paths:
  - /usr/lib/systemd/user/caustics-canvas.service
  - /usr/bin/caustics-canvas
  - /usr/bin/caustics-canvasctl
  - /usr/libexec/topaz/caustics-gpu
---
# The caustics canvas draws the wallpaper

The niri (topaz) session's wallpaper is drawn by the caustics canvas:
`caustics-canvas`, a second host over the bar's engine (ledger 0044),
holds a layer-shell surface on the background layer of every output and
draws it with a compute caustic, and its wallpaper sidecar owns a
socket, `$XDG_RUNTIME_DIR/caustics-canvas.sock`, that scripts drive
through `caustics-canvasctl`: `show <image> [fade <seconds>]` decodes a
PNG, JPEG or JPEG XL and cross-fades to it over the duration given,
`status` reports what is shown. The canvas is built, installed and
linked as part of the bar's set, so the two hosts and their sidecars
are one contract.

`caustics-canvas.service` runs it, gated and wrapped like the bar's
unit (`/usr/libexec/topaz/caustics-gpu <binary>` pins the Vulkan loader
to the integrated GPU on a hybrid laptop). Unlike the bar's, it restarts
on every exit, a refusal and a lost device included: the canvas is
where the lock screen will be drawn, and a session must always get it
back. The sidecar list is the compiled-in default (wallpaper, reload,
glyphs); the polkit and lock sidecars, built and installed with the
set, join by naming the full list in `CAUSTICS_SIDECARS` on the unit
when the session takes those jobs on, each a drop-in removal away from
today's agent and locker. The wallpaper schedule (ledger 0048) is the
first client; the idle fade (ledger 0046, chayang) is the next to move.

`topaz-background.service` orders itself after this unit, and the
canvas keeps the last path it showed in `$XDG_RUNTIME_DIR`, so a
restart re-shows it without the scheduler's help. A checkout of the
project installed under `~/.local` brings its own unit of the same
name, which replaces this one.

Check: the unit carries the wrapper, the gate, `Restart=always` and no
`RestartPreventExitStatus`, sets neither `CAUSTICS_DIR` nor
`CAUSTICS_SIDECARS`, and is enabled; `caustics-canvas` and
`caustics-canvasctl` resolve into the installed set and the client runs
(its usage line); libxkbcommon, which the canvas opens at run time for
its prompt, is installed. Post-boot: the unit is active, the client
reports the schedule's image, and no swaybg runs.
