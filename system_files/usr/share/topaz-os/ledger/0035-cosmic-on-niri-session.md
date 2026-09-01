---
title: COSMIC on niri session
date: 2026-08-21
status: active
paths:
  - /usr/share/wayland-sessions/cosmic-niri.desktop
  - /usr/bin/start-cosmic-niri
  - /usr/libexec/topaz/niri-journal
  - /usr/libexec/topaz/niri-session/cosmic-workspaces
  - /usr/bin/cosmic-ext-alternative-startup
  - /usr/bin/cosmic-idle
  - /etc/niri/config.kdl
  - /etc/niri/cosmic-shell.kdl
  - /usr/share/topaz-os/niri-session-build
---
# COSMIC on niri session

The login screen offers a second COSMIC session, "COSMIC on niri", which
runs the stock COSMIC shell — panel, launcher, notifications, workspaces,
settings — on [niri](https://github.com/YaLTeR/niri), a scrollable-tiling
compositor, instead of cosmic-comp. The stock COSMIC session is untouched
and remains the fallback — nothing here changes what it does. The niri
package contributes a plain-niri session entry of its own, so the greeter
lists three sessions.

This works because cosmic-session already supports alternative
compositors: it takes the compositor to launch as its argument and expects
that compositor to report the resulting Wayland, X11 and IPC socket
addresses back over the `COSMIC_SESSION_SOCK` file descriptor. niri does
not know about that handshake, so the baked niri config spawns
`cosmic-ext-alternative-startup`
(<https://github.com/Drakulix/cosmic-ext-alternative-startup>), a shim that
performs it. There are no protocol shims involved — the COSMIC shell
components talk to niri over the standard `ext-*` protocols.

The lines that turn a niri instance into this session — the environment
import (ledger 0036), the shim spawn, the portal-dialog float rule and the
D-Bus registration for screen sharing (ledger 0039) — live in one
image-owned include, `/etc/niri/cosmic-shell.kdl`, which the baked config
pulls in with `include "cosmic-shell.kdl"`. A personal config is meant to
include the same file rather than copy the lines: a copy once pointed the
shim spawn at a staged binary that had since been removed, and niri 26.04
does not report a startup spawn that fails to exec (its spawner thread
deadlocks on the exec error), so the shell was simply absent after login.
The check validates the include against the baked binary and resolves
every `spawn-at-startup` target to a path the image ships.

Three pieces make it an image feature rather than a hand-assembled trial:

- **niri and xwayland-satellite** come from the locked Fedora package set
  (ledger 0022); the niri binary itself is then replaced by the image's own
  topaz fork of the same release (ledger 0037). niri has no
  built-in XWayland; xwayland-satellite provides it for X11 clients.
- **cosmic-ext-alternative-startup** has no package anywhere, so the image
  builds it (Containerfile `niri-session-build` stage) from a pinned
  upstream commit.
- **cosmic-idle** is built from the topaz fork
  (<https://github.com/davidar/cosmic-idle>, pinned commit on the same
  upstream commit Fedora packages): upstream binds
  `zwlr_output_power_manager_v1` and `wp_single_pixel_buffer_manager_v1`
  unconditionally and aborts when the compositor does not offer them. niri
  implements neither, so the packaged binary dies at session start, taking
  idle locking and idle suspend with it. Patched, both binds are optional:
  without single-pixel-buffer the fade-to-black surface draws a 1×1
  `wl_shm` buffer instead, and without output-power-management screen
  power goes through the compositor's own IPC where there is one
  (`niri msg action power-off-monitors` / `power-on-monitors`, used only
  when `NIRI_SOCKET` is set). The fork binary replaces the packaged one
  image-wide; it is a superset of upstream's behavior, so the COSMIC
  session is unaffected. The first version of this fix covered only the
  output-power bind and had been exercised only under cosmic-comp, where
  the other protocol exists — on niri it still crashed. The check now
  asserts both fallbacks are compiled in, and the fix was run under niri
  before it shipped.

`/usr/bin/start-cosmic-niri` is derived at build time from the packaged
`start-cosmic` by substituting the compositor argument, so both sessions
share one startup environment and upstream changes to it reach both. Two
session-only pieces are added in the derivation:

- The compositor argument is `/usr/libexec/topaz/niri-journal`, a wrapper
  that runs niri with its output in the journal. cosmic-session pipes the
  compositor's stdout and stderr into its process supervisor and forwards
  neither — cosmic-comp logs to journald on its own, so upstream never
  needed to — and niri writes only to stderr, so every line it logged was
  lost. The wrapper strips niri's colour codes and hands the rest to
  `systemd-cat -t niri`; it does not set `NO_COLOR`, because the
  compositor's environment is inherited by every app in the session.
- `/usr/libexec/topaz/niri-session` is put on `PATH` ahead of the packaged
  binaries, for this session only. It holds one shim: `cosmic-workspaces`
  needs cosmic-comp's zcosmic toplevel, workspace and image-capture
  protocols and exits the moment its overlay is toggled on niri. The
  daemon instance cosmic-session starts is passed to the real binary (idle
  and harmless); the panel's Workspaces button, which re-runs the desktop
  file's `Exec=` to toggle the overlay, is routed to niri's own overview
  (`niri msg action toggle-overview`) instead.

`/etc/niri/config.kdl` — niri's system-wide fallback, used by any account
without `~/.config/niri/config.kdl` — is niri's default config with the
bar replaced by the shim, the terminal/launcher binds pointed at COSMIC's,
the lock bind routed through `loginctl lock-session` (cosmic-session runs
the locker as a resident process that answers logind's Lock signal —
spawning a second `cosmic-greeter` takes the session lock and then exits,
leaving niri locked with nothing to unlock it), and two compatibility
rules: libcosmic's frosted-glass windows
publish a rectangular blur region via `ext-background-effect` and round
their corners through a zcosmic protocol only cosmic-comp implements, so
on niri blur is enabled by rule with xray off (the topaz niri build masks
it by the surface's own shape, ledger 0037); and the panel's sandbox
engine is trusted so its applets see the window list (ledger 0038).

`/usr/share/topaz-os/niri-session-build` records the pinned commits.
Standing obligation, enforced by the build: when Fedora bumps cosmic-idle
past the version the fork is based on, the build fails loudly — rebase the
fork onto the new source and move the pin.
