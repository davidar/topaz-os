---
title: niri built from source with topaz patches (tunables, masked blur, trusted sandboxes)
date: 2026-08-22
status: active
paths:
  - /usr/bin/niri
  - /usr/share/topaz-os/niri-session-build
  - /etc/niri/config.kdl
---
# niri built from source with topaz patches (tunables, masked blur, trusted sandboxes)

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

The image builds niri (Containerfile `niri-build` stage) from the topaz
fork, <https://github.com/davidar/niri>, at a pinned commit on top of the
upstream release Fedora's package is built from, and the built binary
replaces `/usr/bin/niri`; everything else from the niri package — session
files, units, default config, docs — is unchanged. `/etc/niri/config.kdl`
(the baked fallback, ledger 0035) carries every key at its upstream
default so the knobs are documented where they are set, and the build's
`niri validate` proves the baked binary accepts them. Per-user configs
override it entirely, as before.

The fork carries further changes, configurable where a choice exists
and defaulting to upstream behaviour:

- **Background effects masked by surface alpha.** niri draws blur (and
  noise/saturation) over the rectangle a surface requests. libcosmic
  draws its rounded corners client-side and requests a rectangular blur
  region, so a square slab of blur showed behind every rounded corner on
  niri; the only upstream remedy is restating each client's radius in a
  window rule. The patch samples the surface's own texture and limits
  the effect to pixels the surface covers, the way Hyprland's stencil
  pass does. Coverage, not opacity: a translucent surface keeps full
  blur; only pixels below `mask-threshold` alpha (default 0.25) ramp to
  none. `mask`/`mask-threshold` live in every `background-effect` rule
  block, hot-reloaded. The former corner-radius rule in the baked config
  is gone. Two details make it hold on real COSMIC surfaces: the mask
  texture is looked up through Smithay's multi-GPU renderer (the TTY
  backend's, under which the plain lookup found nothing and the mask
  silently switched off), and a surface's declared opaque region is not
  trusted — libcosmic's layer surfaces (the OSD, the launcher) declare
  themselves fully opaque over transparent corners, so only a buffer
  format without alpha disqualifies a surface, and such surfaces are
  rendered without opaque regions so the masked effect beneath their
  corners is not culled. Each surface's mask outcome is logged once per
  change at debug level, so the next silent failure names itself.
- **Trusted sandbox engines.** Clients connecting through a
  `wp_security_context_v1` listener are restricted to the unprivileged
  protocol set in upstream niri, unconditionally. COSMIC's panel hands
  every applet such a socket, which is why the dock, workspaces and
  minimize applets saw no windows on niri even once they no longer
  crashed (ledger 0038). `security-context { trust-sandbox-engine
  "<name>" }` lifts the restriction for clients of a named engine.
  Safe by construction: only unrestricted clients can create security
  contexts, so a sandboxed client cannot label itself. Default: no
  engines trusted, i.e. upstream behaviour.
- **A lock in flight survives a skipped frame.** Upstream abandons a
  session lock when an output fails to render the locked frame. The
  usual trigger is the lock requested for suspend: logind revokes DRM
  master before the locked frame is queued, the flip fails, and the
  machine resumes unlocked. A skipped render now leaves the lock waiting
  (input is already blocked); the redraw on resume confirms it.
- **`ext-image-capture-source-v1` and `ext-image-copy-capture-v1`.**
  The standard Wayland screen-capture protocols, which COSMIC's
  screenshot portal, `cosmic-screenshot` and the dock's window
  thumbnails all require and upstream niri does not offer (its capture
  path is the Mutter ScreenCast D-Bus API, ledger 0039). Based on an
  open upstream pull request, adapted to the Smithay revision niri
  pins, with two fixes found in the VM harness: sessions were dropped
  the moment they were created (every capture ended after one frame),
  and only one shm format was rendered while clients ignore the
  advertised list — all four common 8888 layouts are now accepted and
  advertised. Shared-memory capture only: dmabuf capture is disabled
  until it is verified on real hardware.
- **A spawn that fails to exec is reported, not deadlocked.** When a
  command niri spawns cannot be executed (a stale path in a
  `spawn-at-startup`, say), the intermediate process that the
  systemd-scope spawn path forks waited for a go-ahead that could only
  arrive after the spawn had returned, while the spawn waited for that
  process: the spawner thread hung for good, one orphaned `niri`
  process was left behind per failed spawn, and the "error spawning"
  warning never reached the journal — which is how a missing startup
  shim once cost a whole login with nothing logged (ledger 0035). The
  intermediate process now also watches the child's pidfd and exits as
  soon as the child does, so a failed spawn returns at once with its
  warning; a regression test covers it.
- **A `has-sibling` window-rule matcher.** `match has-sibling=true`
  selects a window whose client already had a mapped window when this
  one appeared — a browser's extension popout or a page's popup, which
  is subordinate to the window that opened it but usually sets no xdg
  parent and no fixed size, so upstream tiles it into a new column. The
  fact is captured when the window is created (and again when it unmaps
  and reappears) and kept for its lifetime, so rules on it are stable.
  `/etc/niri/config.kdl` uses it to float Firefox's secondary windows
  without matching on window titles.

The fork tracks the upstream release tag; the upstream project's
contribution stance means the changes stay there rather than going up.
`/usr/share/topaz-os/niri-session-build` records the pinned commit.
Standing obligation, enforced by the build: when Fedora bumps niri past
the release the fork is based on, the build fails loudly — rebase the
fork onto the new release and move `NIRI_REF`. `topaz check` asserts
the installed binary differs from the package's, that the package version
still matches the fork base, and that its libraries resolve (the
builder's Fedora release must track the image's, as for the other built
stages).
