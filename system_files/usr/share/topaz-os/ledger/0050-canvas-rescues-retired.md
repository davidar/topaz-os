---
title: The canvas's rescues leave — swaylock, cosmic-osd and swaybg
date: 2026-10-31
status: active
paths:
  - /etc/pam.d/caustics-lock
  - /usr/lib/systemd/user/caustics-canvas.service
  - /usr/lib/systemd/user-preset/45-topaz.preset
---
# The canvas's rescues leave — swaylock, cosmic-osd and swaybg

When the caustics canvas took the niri (topaz) session's wallpaper, idle
dim, polkit prompt and lock screen (ledger 0049), the three tools it
replaced stayed installed and idle as rescues until the canvas had been
lived in: swaylock behind `topaz-locker.service`, cosmic-osd's polkit
agent behind `topaz-polkit-agent.service`, and swaybg. The canvas has
now locked and unlocked on hardware through an idle lock and a suspend
cycle, with the password and the fingerprint, and prompted for polkit.
The rescues go: the three packages, the two units, the locker wrapper
(`/usr/libexec/topaz/locker`) and swaylock's config (`/etc/swaylock/config`).

One thing swaylock left behind had become load-bearing. The canvas's lock
sidecar runs its PAM conversation as a named service, and its default
name is `swaylock`: `/etc/pam.d/swaylock`, a file the swaylock package
owned and the build rewrote onto the fingerprint-free `password-auth`
stack. Without the package the name would resolve to PAM's `other`
fallback, which denies everything, and a typed password would never
unlock the screen again. The image now ships the lock's own file,
`/etc/pam.d/caustics-lock`, on the same stack, and names it on
`caustics-canvas.service` with `CAUSTICS_LOCK_PAM_SERVICE=caustics-lock`.
A checkout of caustics installed under `~/.local` replaces that unit with
its own (ledger 0049), which names no PAM service: its drop-in must carry
the same line, or the lock asks for a file this image does not have.

Nothing else in the session changes: swayidle's `before-sleep` still runs
`caustics-canvasctl lock --wait`, the idle dim and the lock bind still go
through `loginctl lock-session`, and polkit prompts still come from the
canvas's agent. There is no second locker to fall back on; if the canvas
cannot run, the compositor keeps the session locked (ledger 0049) and the
console (VT 2) is the way in.

Check: swaylock, swaybg, cosmic-osd and chayang are not installed, the
two units, the wrapper and the config are absent, `/etc/pam.d/swaylock`
is absent, `/etc/pam.d/caustics-lock` includes `password-auth`, the
canvas unit names the service, and `password-auth` carries no
`pam_fprintd`. Post-boot: the VM lock-unlock suite refuses a wrong
password and accepts the right one through the new stack; the
boot-verify suite finds none of the three binaries.
