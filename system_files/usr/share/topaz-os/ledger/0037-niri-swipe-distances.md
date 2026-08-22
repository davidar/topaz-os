---
title: niri built from source with its hardcoded tunables promoted to config
date: 2026-08-22
status: active
paths:
  - /usr/bin/niri
  - /usr/share/topaz-os/niri-session-build
  - /etc/niri/config.kdl
---
# niri built from source with its hardcoded tunables promoted to config

niri is configured almost entirely from its config file, with one class of
exception: the numbers that shape how gestures and interactions *feel* are
compile-time constants. The one that prompted this: the touchpad swipe
distances — 300 logical pixels of finger travel per workspace, 1200 per
screen width of view, 300 for the overview. On release the gesture
projects where the fingers would coast to and rounds to the nearest unit,
so a slow swipe that stops short of half the distance snaps back, and
nothing in the config reaches the number (touchpad acceleration does not
apply either — the gesture deliberately uses unaccelerated deltas). The
upstream pull request that would add gesture settings (niri-wm/niri#3771)
has sat as a large draft for months without maintainer engagement.

An audit of the source (`~/cosmic-debug/niri-config-sweep.md` on the
development machine) found 41 such constants; the 28 that are behavioural
rather than implementation detail are promoted to config keys here, each
defaulting to the upstream value and merged and hot-reloaded like every
other niri option:

- `gestures { touchpad-swipe { … } }`: `workspace-movement`,
  `view-movement`, `overview-movement` (the distances above),
  `workspace-fingers` / `overview-fingers` (which finger count drives
  which gesture; upstream hardwires 3 and 4), `deceleration` and
  `velocity-window-ms` (the fling projection: how much a flick counts
  for), `workspace-rubber-band` / `overview-rubber-band`
  (`stiffness=` `limit=` overscroll feel past the ends).
- `gestures { dnd-edge-workspace-switch { workspace-movement } }` — the
  drag distance per workspace during drag-and-drop edge scrolling, which
  upstream duplicates from `max-speed` as a separate constant.
- `gestures { hot-corners { trigger-size } }` — the corner hit area,
  upstream exactly one logical pixel.
- `gestures { pointer-drag { direction-lock-distance } }` — how far a
  Mod+mouse drag moves before it locks to horizontal or vertical.
- `gestures { touch { long-press-ms } }` — the touchscreen hold before a
  window in the overview starts moving.
- `layout { … }`: `interactive-move-threshold` (drag distance before a
  tiled window detaches), `interactive-move-opacity`,
  `interactive-move-rubber-band`, `floating-move-step` (directional move
  actions on floating windows), `resize-animation-threshold` and
  `move-animation-threshold` (changes smaller than this don't animate).
- `input { double-click-time-ms }`.
- `overview { scroll-cooldown-ms }` — repeat cooldown for wheel
  scrolling in the overview.
- `animations { window-open { scale-from } window-close { scale-to } }`
  — the curve shape; the timing was already configurable.
- `recent-windows { edge-peek }` — how much of the neighbouring window
  previews shows at the screen edges in the window switcher.
- `timeouts { xdg-activation-token-ms lock-surface-ms }`.

The image builds niri (Containerfile `niri-build` stage) from the
upstream commit Fedora's package is built from, with
`build_files/niri-tunables.patch` applied, and the built binary
replaces `/usr/bin/niri`; everything else from the niri package — session
files, units, default config, docs — is unchanged. `/etc/niri/config.kdl`
(the baked fallback, ledger 0035) carries every key at its upstream
default so the knobs are documented where they are set, and the build's
`niri validate` proves the baked binary accepts them. Per-user configs
override it entirely, as before.

The patch is a patch file, not a fork repository: it tracks the upstream
tag, and the upstream project's contribution stance means it stays local.
`/usr/share/topaz-os/niri-session-build` records the pinned commit.
Standing obligation, enforced by the build: when Fedora bumps niri past
the release the patch is based on, the build fails loudly — re-verify the
patch against the new source and move `NIRI_REF`. `topaz check` asserts
the installed binary differs from the package's, that the package version
still matches the patch base, and that its libraries resolve (the
builder's Fedora release must track the image's, as for the other built
stages).
