---
title: Fingerprint unlock on the COSMIC lock screen
date: 2026-07-28
status: active
paths:
  - /usr/share/polkit-1/rules.d/60-topaz-cosmic-greeter-fprintd.rules
---
# Fingerprint unlock on the COSMIC lock screen

The COSMIC lock screen never accepted enrolled fingerprints, silently
falling through to the password prompt. PAM was not the problem:
`/etc/pam.d/cosmic-greeter` substacks `system-auth`, which carries
`pam_fprintd.so` (ledger 0006's timeout tweak included).

The failure was one polkit layer down. Under GDM (this image's display
manager), `cosmic-greeter-daemon` never runs; the lock screen is a
`cosmic-greeter` process running as the session user that performs the
PAM transaction in-process. But cosmic-session spawns it into the systemd
user manager (`user@.service` app.slice) rather than the logind session
scope, so polkit sees a subject with *no session*. fprintd's
`net.reactivated.fprint.device.verify` action defaults to
`allow_active=yes` / `allow_any=no` — and with no session, `allow_any`
applies:

    fprintd: Authorization denied to :1.923 to call method
    'ListEnrolledFingers' ... Not Authorized: net.reactivated.fprint.device.verify

GDM's own fingerprint prompt is immune because its auth worker runs
inside the greeter's active seat session.

The shipped rule grants exactly `device.verify` to subjects whose
executable is `/usr/bin/cosmic-greeter`. That permission only allows
verifying the calling user's own enrolled prints — claiming another
user's requires `device.setusername`, which stays at its `auth_admin`
default. Verified live on 2026-07-28: with the rule installed, the lock
screen unlocks from the enrolled finger; without it, the polkit denial
above appears in the journal.

Upstream candidates: cosmic-session could spawn the locker inside the
session scope, or cosmic-greeter could ship a rule like this one.
