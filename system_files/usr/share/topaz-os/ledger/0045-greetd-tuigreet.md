---
title: greetd with tuigreet as the display manager
date: 2026-10-20
status: active
paths:
  - /etc/systemd/system/display-manager.service
  - /etc/greetd/config.toml
  - /etc/pam.d/greetd
  - /usr/lib/tmpfiles.d/topaz-greetd-home.conf
  - /usr/share/wayland-sessions/topaz.desktop
---
# greetd with tuigreet as the display manager

The login screen is greetd running [tuigreet](https://github.com/apognu/tuigreet)
on VT 1 (Fedora's package, 0.9.1), replacing the base image's GDM.
`display-manager.service` resolves to `greetd.service`; `gdm.service`
and `cosmic-greeter.service` are disabled.

Why. The image had already left GDM on hardware: since August the
machine logged in through greetd with cosmic-greeter (ledger 0034), a
hand-made trial the image never adopted (ledger 0004 kept GDM, and
`topaz check` enforced it). cosmic-greeter needs a compositor of its own
and brought three forks with it (greeter, cosmic-comp, smithay) for a
screen that is shown for a few seconds a day. tuigreet is a terminal
program: no compositor, no toolkit, no GPU driver in the login path, so
it shares nothing with the sessions it starts, and a broken session
cannot take the login screen with it. Among greetd greeters it is the one
with a session list, a power menu and memory of the last login.

What it does. Sessions come from `/usr/share/wayland-sessions` and
`/usr/share/xsessions` — GNOME, COSMIC, COSMIC on niri, niri, niri
(topaz) — with F3 to switch and F12 for power. `--remember` and
`--remember-user-session` prefill the last user and preselect that user's
last session, and a remembered user goes straight to the password
prompt. Fedora's build keeps those records in the greeter's home
(`/var/lib/greetd/tuigreet-lastuser`, `tuigreet-lastsession-path-<user>`)
rather than upstream's `/var/cache/tuigreet`. `/var` ships empty (ledger
0024), the package's tmpfiles.d rule only relabels an existing home, and
the portal mask (ledger 0024) created it as a root-owned parent — so the
greeter could not write to its own home and silently forgot every login.
A tmpfiles.d rule now creates the directory for the greeter user.

Session identity. tuigreet sets `XDG_SESSION_DESKTOP` to the session
file's name (its stem), where cosmic-greeter used the entry's first
`DesktopNames` value and GDM the stem as well. The niri (topaz) session's
units are gated on `XDG_SESSION_DESKTOP=topaz` (ledger 0041), so its
entry is now `topaz.desktop` (was `topaz-niri.desktop`; `DesktopNames`
stays `topaz`, so either greeter starts the same units).

Password only. Fedora's `/etc/pam.d/greetd` substacks `system-auth`,
which carries `pam_fprintd.so timeout=5` (ledger 0006) ahead of the
password module, and tuigreet runs that conversation in order: every
login would wait 5 s before the password prompt, for a fingerprint that
cannot unlock the keyring anyway (GDM and cosmic-greeter ran the two in
parallel). The auth stack substacks `password-auth` instead — the same
stack without the fingerprint module, as swaylock's does (ledger 0041);
the session stack keeps `system-auth` and `pam_gnome_keyring`, so the
typed password unlocks the keyring. Fingerprint stays for unlocking,
once the session has a locker that offers it.

What stays. The `cosmic-greeter` package remains (a hard dependency of
`cosmic-session`) as the lock screen of the COSMIC fallback sessions,
and the fork build (ledger 0034) with it, for its locker fixes; the
niri (topaz) session locks through the caustics canvas (ledger 0049). Rescue: VT 2,
`systemctl disable greetd && systemctl enable gdm`, reboot. On a
machine that set its own display manager by hand (the August trial), the
local `/etc/systemd/system/display-manager.service` symlink wins over
the image's at every update; a one-time `systemctl disable
cosmic-greeter.service && systemctl enable greetd.service` adopts the
image's choice, and `topaz check` reports the mismatch until then.

Check: the alias resolves to greetd, GDM and cosmic-greeter are
disabled, the greetd config runs tuigreet on VT 1 as the greetd user
with both remember flags, the binary and the home rule exist, greetd's
auth stack is `password-auth` with no path to `system-auth`, and the
session entry is `topaz.desktop`. Post-boot: the VM harness logs out
and back in at tuigreet (relogin-cycle) with a seeded remembered user,
waiting for the password prompt on the console before typing, and
asserts the session comes up with the right identity and that the
greeter rewrote its records on login (a write it fails silently).
