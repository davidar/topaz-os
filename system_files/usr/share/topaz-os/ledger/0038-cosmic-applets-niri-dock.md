---
title: cosmic-applets rebuilt so the dock works on niri
date: 2026-08-22
status: active
paths:
  - /usr/bin/cosmic-applets
  - /usr/share/topaz-os/niri-session-build
  - /etc/niri/config.kdl
---
# cosmic-applets rebuilt so the dock works on niri

In the COSMIC-on-niri session (ledger 0035) the panel's dock
(cosmic-app-list) came up empty and the minimize applet died: both
unconditionally bind `zcosmic_toplevel_manager_v1`, a cosmic-comp-only
protocol, and abort when it is missing. A second abort sat behind the
first — window thumbnails unwrap an image-copy-capture session that niri
does not offer — and would have killed the dock on the first hover.

The image builds cosmic-applets (Containerfile `cosmic-applets-build`
stage) from the topaz fork, <https://github.com/davidar/cosmic-applets>,
at a pinned commit on top of the upstream commit Fedora's package is
built from, and installs the one multicall binary over
`/usr/bin/cosmic-applets`; the packaged applet names are symlinks into it
and stay. The fork binds the zcosmic manager
optionally and keeps that path verbatim when it exists, so the stock
COSMIC session is unaffected. Without it, windows are listed through
`ext-foreign-toplevel-list` and activated/minimized/closed through
`wlr-foreign-toplevel-management`, which niri implements; the two
protocols hand out unrelated handles for the same window, so they are
matched on `(app_id, title)` with announcement order as the tiebreak.
Known limit: two windows with identical app_id and title can swap.
Thumbnails are off on niri (no capture protocol), and niri has no
minimize, so the minimize applet stays empty there.

The applet binding alone is not enough: the panel gives each applet a
`wp_security_context` socket, and niri restricts such clients from the
toplevel and workspace protocols. The topaz niri build trusts the
panel's sandbox engine by name (ledger 0037), configured in the baked
`/etc/niri/config.kdl`; per-user configs need the same
`security-context` block.

`/usr/share/topaz-os/niri-session-build` records the pinned commit.
Standing obligation, enforced by the build: when Fedora bumps
cosmic-applets past the version the fork is based on, the build fails
loudly — rebase the fork and move `COSMIC_APPLETS_REF`. `topaz check`
asserts the installed binary differs from the package's, the version
still matches the fork base, the wlr fallback is present, the applet
symlinks resolve into it, and its libraries resolve.
