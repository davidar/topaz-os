---
title: speech-dispatcher socket enabled for user sessions
date: 2026-07-25
status: active
paths:
  - /usr/lib/systemd/user-preset/45-topaz.preset
---
# speech-dispatcher socket enabled for user sessions

Fedora ships speech-dispatcher socket activation disabled by default, which
makes Flatpak browsers (notably Firefox) log complaints and lose
text-to-speech support. Firefox's Flatpak already has the
`xdg-run/speech-dispatcher:ro` permission, so the only missing piece is the
socket.

A systemd user preset enables `speech-dispatcher.socket` for fresh user
instances. Users who have already made an explicit enable/disable choice are
unaffected (presets only apply where no state exists).
