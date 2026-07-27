---
title: Transient dev overlay workflow (topaz dev)
date: 2026-07-27
status: active
paths:
  - /usr/bin/topaz
---
# Transient dev overlay workflow (topaz dev)

This image is developed live: components like the compositor are forked,
rebuilt locally in seconds, and daily-driven before any change is frozen
into a signed image build. The `topaz dev` subcommands make that workflow
first-class without weakening the image's integrity story:

- `topaz dev on` arms a transient overlay on `/usr` (`bootc usroverlay`).
  Nothing written there survives a reboot, so the signed image is always
  one reboot away — the overlay is a scratchpad, not a fork of the OS.
- `topaz dev install <file> [dest]` copies a locally built binary over its
  image counterpart and records it (path, sha256, source, timestamp) in a
  manifest under `/run/topaz-dev` — tmpfs, so the record dies with the
  overlay it describes.
- `topaz dev status` / `topaz dev off` report the deviation and how to
  end it. `topaz check` prints a loud banner whenever an overlay is
  active, so a hacked system can never present itself as matching its
  ledger silently.

The graduation path for anything daily-driven this way is unchanged:
a CI-built artifact in the image plus the usual ledger entry, `topaz
check` assertion, and README bullet. The build-time assertion for this
entry is that `bootc` (which provides the overlay mechanism) is present
in the image.
