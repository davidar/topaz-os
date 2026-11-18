---
title: Secret Service (oo7-daemon) enabled in every session
date: 2026-11-18
status: active
paths:
  - /usr/lib/systemd/user-preset/45-topaz.preset
  - /etc/systemd/user/default.target.wants/oo7-daemon.service
---
# Secret Service (oo7-daemon) enabled in every session

`oo7-daemon.service` is enabled for all users (user preset and a global
enable at build time), so the Secret Service starts with the user
manager in every session rather than only in GNOME's.

Why. With Fedora 45 the base replaced gnome-keyring with oo7.
gnome-keyring's PAM module started its daemon itself; `pam_oo7` does
not. It hands the login password to a helper (`oo7-daemon-login`) that
holds it for two minutes waiting for a daemon to collect it, and the
daemon is started by `gnome-session-services.target` alone: the unit is
not enabled by any preset and there is no D-Bus activation file for
`org.freedesktop.secrets`. In the niri (topaz) session (ledger 0041)
nothing therefore owned the name. The helper timed out without a word,
the PAM log still read "Successfully sent secret to oo7 daemon", the
keyring left by gnome-keyring was never migrated, and applications that
store logins through the Secret Service or the Secret portal had no
backend.

What it does. The daemon starts at `default.target`, inside the
helper's window, takes the login password and unlocks the `login`
collection without a prompt (ledger 0045 keeps the keyring module in
greetd's stack). On first unlock it converts a gnome-keyring file in
`~/.local/share/keyrings/` into `keyrings/v1/`, leaving the old file in
place beside a `.migrated` stamp. When no password arrives (a
fingerprint or automatic login), the collection stays locked and the
daemon asks through `org.gnome.keyring.SystemPrompter` (gcr-prompter) at
first use.

Check: the unit is linked into the global `default.target.wants`, the
preset names it, the unit still claims `org.freedesktop.secrets`, and
greetd's session stack still carries `pam_oo7.so auto_start`. The build
also fails if the base starts activating the name over D-Bus, at which
point this entry is redundant. Post-boot: the VM harness asserts the
unit is active and owns the name; the unprompted unlock after a typed
password is a hardware check.
