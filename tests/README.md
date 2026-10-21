# VM verification harness

Boots the locally built image in a QEMU VM and machine-checks the
post-boot state over ssh — the assertable part of what otherwise needs a
human at the console after every reboot: session environment import,
portal wiring, bus name ownership, failed units, lock state, and
`topaz check` itself. A private VNC socket gives the harness
hypervisor-side screenshots, and QMP adds input injection and precisely
timed suspend/wake, so lock/suspend race regressions become scriptable.

Quick start (from the repo root, with `localhost/topaz-os:test` built):

    bash tests/run.sh all          # or: just verify-vm

The disk build step runs bootc-image-builder as rootful podman (sudo);
everything else is rootless. Artifacts live in `tests/.artifacts/`
(gitignored): the test disk, per-checkout ssh key, serial log, and
screendumps.

Several guests can run at once off the one test disk: `TOPAZ_TEST_ID=N`
(default 0) gives guest N its own ssh port (2233+N), QMP and VNC sockets,
pidfile, serial log and UEFI variables under `.artifacts/N/` — id 0 keeps
the original paths — and every `run.sh` command acts on that guest. Each
guest boots with `-snapshot`, so they never write the shared disk; size
`TOPAZ_TEST_RAM` (default 8G) to what the host can hold.

A companion repo can bake its own payload into the test image rather than
copy it into every booted guest: stage a directory holding an executable
`install.sh` (run as root, from that directory, at image build time) and
build with `TOPAZ_TEST_EXTRA=<dir> tests/run.sh image`, then `tests/run.sh
disk`. Unset, the image is unchanged.

Which session the autologin runs is baked into the test image too:
`TOPAZ_TEST_SESSION=topaz-niri tests/run.sh image` selects the niri (topaz)
session (ledger 0041, the caustics bar and systemd user units) instead of
the default COSMIC-on-niri one; `boot-verify` reads the choice back from
the guest and asserts the matching shell. Pass the same variable to every
later `run.sh` invocation, or the harness rebuilds the image for the
default session and the disk no longer matches it.

Pieces:

- `Containerfile.test` — derived test image, never published: greetd
  autologin into the chosen session, sshd, display manager
  flipped to cosmic-greeter (so `topaz check`'s enforced-GDM claim fails
  here by design, matching the greetd trial on hardware).
- `disk-test.toml.in` — bootc-image-builder config template; the runner
  injects the ssh public key and a `tester` login user at disk-build
  time so the image layer ships no users and `/var` stays empty.
- `run.sh`, `lib.sh`, `qmp.py`, `screendump.py`, `png_mean.py` — VM
  lifecycle, ssh plumbing, QMP control, VNC frame capture, a screenshot
  brightness probe, and the assertion helpers suites use.
- `suites/boot-verify.sh` — first suite: a healthy first boot into the
  autologin session.
- `suites/lock-unlock.sh` — locks the session through logind, types a
  wrong and then the right password at the lock screen, and asserts the
  lock holds and clears as seen from outside: in niri (topaz) the
  swaylock unit active exactly while locked and idle again afterwards
  with no restarts; in COSMIC on niri LockedHint, the resident locker's
  lockfile, and the same locker process at the end.
- `suites/idle-fade.sh` — niri (topaz) only: writes the test user's
  `~/.config/topaz/session.conf` to run the idle stages in seconds, asserts
  swayidle picked them up, measures the screen darkening mid-fade
  (`png_mean.py`), cancels one fade with a keypress and lets the next end
  in the lock, then clears it with the password and removes the file.
- `suites/relogin-cycle.sh` — logs out through niri and back in at
  cosmic-greeter: the session teardown (ledger 0036), the greeter coming
  up, and a real greeter login of the session under test (identity
  variables, display import, shell units, no failed units or coredumps).

The two console suites type into the guest over QMP and set a password
for `tester` at their start (the disk ships it without one); input is
letters and digits only. Run them against a running guest, or have the
harness boot one:

    bash tests/run.sh suite lock-unlock        # guest already started
    bash tests/run.sh all relogin-cycle

Each changes session state, so start each from a fresh boot (`run.sh
stop`, then `start`). Their lock-screen and greeter screendumps need the
hypervisor-side view (the VNC socket of the egl display mode); in sdl
mode they skip those captures and say so.

Planned: `lock-chain` (lock/suspend/wake races driven by QMP timing).

The guest needs working GL (virgl) or the session itself misbehaves; on
a GPU-less host — CI runners — the harness detects the missing render
node and hosts the GL context on llvmpipe via SDL's offscreen driver,
with screenshots captured inside the guest instead of over VNC
(`TOPAZ_TEST_DISPLAY` overrides). KVM is still required; GitHub's
standard Linux runners have it.

Out of scope by design: NVIDIA paths, real DRM-master timing,
fingerprint, and anything aesthetic — those remain hardware checks.
