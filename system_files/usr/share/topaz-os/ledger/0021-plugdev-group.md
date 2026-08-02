---
title: plugdev group declared for base-image udev rules
date: 2026-08-02
status: active
paths:
  - /usr/lib/sysusers.d/topaz-plugdev.conf
---
# plugdev group declared for base-image udev rules

The base image ships udev rules that reference the Debian-style `plugdev`
group — `70-u2f.rules` (FIDO/U2F tokens), `50-zsa.rules` (ZSA keyboards)
and `10-switch.rules` (Nintendo controllers) — but Fedora defines no such
group. Every udev rules load logged ~100 "Failed to resolve group
'plugdev'" errors (measured 107 on a 2026-08-02 boot), and the rules'
group grants were dead letters.

A `sysusers.d` fragment declares the group so systemd creates it at boot.
This is the fix systemd upstream recommends for rules that reference
optional groups, and it is inert for users who never plug in the affected
devices: the rules also grant `uaccess`, so console users were already
covered — the group existing merely stops the error spam and makes
membership-based access possible.

The remaining "unknown group" messages at early boot (core groups like
`disk` and `audio`) come from initrd-phase service starts before `/etc`
is mounted; they are ordinary ostree boot ordering, resolve themselves,
and are not in scope here. Upstream candidate: report the missing group
to Universal Blue, who ship the rules files.
