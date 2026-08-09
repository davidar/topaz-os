---
title: Fingerprint PAM timeout reduced to 5 seconds
date: 2026-07-25
status: active
paths:
  - /etc/pam.d/system-auth
  - /etc/authselect/custom/local-custom
---
# Fingerprint PAM timeout reduced to 5 seconds

PAM serializes authentication methods: with fingerprint enrolled, the password
prompt is blocked until pam_fprintd times out, which defaults to 30 seconds.
In practice this means a user who wants to type their password (wet fingers,
external keyboard, reader glitch) waits half a minute.

The build generates a custom authselect profile (`custom/local-custom`) from
the base `local` profile and selects it with features `with-fingerprint
with-silent-lastlog with-mdns4`. Every file in the profile is a symlink back
to the base profile — upstream profile changes flow through automatically —
except `system-auth`, which is copied and patched to add `pam_fprintd.so
timeout=5`. A grep guard in `configure.sh` fails the build if upstream reshapes
the pam_fprintd line. The password prompt appears after 5 seconds if the
fingerprint reader is not used.
