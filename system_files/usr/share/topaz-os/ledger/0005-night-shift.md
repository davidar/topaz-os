---
title: Night-shift triage with a pluggable analysis backend
date: 2026-07-25
status: active
paths:
  - /usr/libexec/topaz-nightshift
  - /usr/lib/systemd/user/topaz-nightshift.service
  - /usr/lib/systemd/user/topaz-nightshift.timer
  - /usr/share/topaz-os/nightshift.conf.example
  - /usr/share/topaz-os/nightshift-prompt.md
  - /usr/bin/topaz
---
# Night-shift triage with a pluggable analysis backend

The image ships a daily "night shift": a systemd user timer that collects a
digest of system events (failed units, journal errors, OOM interventions,
staged deployments, disk usage, and a self-check that the system still
matches this ledger) and writes a morning report to
`~/.local/state/topaz/reports/`.

Design decisions:

- **Disabled by default.** A background triage timer is opt-in, per user:
  `topaz nightshift enable`.
- **No analysis tool is baked into the image.** Triage is a user-configured
  hook (`TRIAGE_CMD` in `~/.config/topaz/nightshift.conf`): any command that
  reads the digest on stdin and writes a report on stdout. This keeps the
  image tool-agnostic — an AI coding agent, a local model, or a plain script
  all plug in equally — and avoids baking fast-moving tools into an immutable
  `/usr` where their self-update mechanisms cannot work. Without a configured
  hook, raw digests are saved.
- **The image never auto-runs remote installers.** Whatever backend the user
  chooses, they install it themselves in mutable space.
- **The night shift has memory.** The digest includes the previous morning
  report and, if the user keeps one, `~/.config/topaz/nightshift-notes.md` —
  standing notes on what is expected: known-benign log signatures, planned
  transitions, watch items. Nightly triage becomes a continuing
  investigation instead of a stateless snapshot, and day-time work has a
  handoff channel to the night shift. Both are plain-text digest sections; a
  non-LLM backend can ignore them, and no note content ships in the image.
- **`topaz check` closes the loop.** Every deviation this ledger records is
  verified at image build time and re-verified by each night-shift run, so
  drift between the ledger's claims and reality is detected rather than
  assumed absent.
