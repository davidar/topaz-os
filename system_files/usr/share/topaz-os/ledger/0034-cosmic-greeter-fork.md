---
title: cosmic-greeter built from the topaz fork
date: 2026-08-16
status: active
paths:
  - /usr/bin/cosmic-greeter
  - /usr/share/topaz-os/cosmic-greeter-fork
---
# cosmic-greeter built from the topaz fork

The greeter/lock-screen binary is not Fedora's: it is compiled in the
image build (Containerfile `greeter-build` stage) from a pinned commit of
<https://github.com/davidar/cosmic-greeter>, branch `auth-rearm`, which
carries three small patches on top of the packaged 1.5.0:

- **JPEG XL wallpaper decoding.** Upstream hands wallpaper bytes to the
  image crate, which cannot decode JXL, so distributions shipping JXL
  wallpapers (Bluefin, Aurora) get a blank grey background on both the
  greeter and the lock screen while the desktop renders fine — cosmic-bg
  registers jxl-oxide's image-crate decoding hook and cosmic-greeter did
  not. The fork registers the same hook. Pending upstream; drop the
  patch when merged.
- **Fingerprint re-arm on wake.** The locker runs a single PAM
  conversation per lock, so the fingerprint prompt expires after about a
  minute and never returns — coming back to a locked screen left
  password as the only option. The fork restarts the conversation on
  resume from suspend and when input arrives after a 30 s gap (waking
  the screen counts), re-arming every PAM module. Answers
  pop-os/cosmic-greeter#99/#413/#207. Side effects: each re-arm logs a
  deliberate pam_unix conversation failure, and libpam's ~2 s fail
  delay on that failure means the reader arms ~2.5 s after the first
  input (accepted trade-off; overriding PAM_FAIL_DELAY was declined to
  keep the patch series minimal).
- **Lock state reported to logind** (`LockedHint`), so `loginctl` and
  anything watching the session sees the lock.
- **Lock state follows the compositor.** The locker ignored the
  ext-session-lock `finished` event (the compositor abandoning a lock it
  never confirmed), so a failed lock left it believing the session was
  locked — PAM conversation running, `LockedHint` set, and a stale
  lockfile that made the next locker instance take the session lock the
  moment it started. Resetting the locker's own state in-process proved
  insufficient: the toolkit's session-lock state, the PAM conversation
  and the logind listener can all be left broken after `finished`, and
  every later lock signal becomes a silent no-op (observed as a locker
  that ignored lock requests for 36 hours after a suspend abandoned a
  lock in flight). On `finished` the locker now removes its lockfile (so
  the replacement waits for a lock signal instead of recovering a dead
  lock), clears `LockedHint` with a bounded wait, and exits non-zero so
  the session's process manager restarts a clean instance (launch-pad
  restarts only on unsuccessful exit). Paired with this, a logind failure
  no longer exits the process while a lock is held (the compositor would
  stay locked with no client to unlock it); the lock screen keeps working
  with a password and the locker exits once unlocked.

Only the UI binary is replaced; `cosmic-greeter-daemon` stays Fedora's —
none of the patches touch it.

Provenance: `/usr/share/topaz-os/cosmic-greeter-fork` records the repo,
the exact commit, and the Fedora base version the fork tracks. As with
the cosmic-comp fork (ledger 0015), the build fails loudly if Fedora
ships a different base version (forcing a rebase), the builder's Fedora
release is pinned to the base image's (glibc), and `topaz check` asserts
the binary deviates from the packaged one, the version pin holds, and
all libraries resolve.
