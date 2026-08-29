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

Pieces:

- `Containerfile.test` — derived test image, never published: greetd
  autologin into the COSMIC-on-niri session, sshd, display manager
  flipped to cosmic-greeter (so `topaz check`'s enforced-GDM claim fails
  here by design, matching the greetd trial on hardware).
- `disk-test.toml.in` — bootc-image-builder config template; the runner
  injects the ssh public key and a `tester` login user at disk-build
  time so the image layer ships no users and `/var` stays empty.
- `run.sh`, `lib.sh`, `qmp.py`, `screendump.py` — VM lifecycle, ssh
  plumbing, QMP control, VNC frame capture, and the assertion helpers
  suites use.
- `suites/boot-verify.sh` — first suite: a healthy first boot into the
  autologin session.

Planned suites: `relogin-cycle` (session teardown, ledger 0036) and
`lock-chain` (lock/suspend/wake races driven by QMP timing).

The guest needs working GL (virgl) or the session itself misbehaves; on
a GPU-less host — CI runners — the harness detects the missing render
node and hosts the GL context on llvmpipe via SDL's offscreen driver,
with screenshots captured inside the guest instead of over VNC
(`TOPAZ_TEST_DISPLAY` overrides). KVM is still required; GitHub's
standard Linux runners have it.

Out of scope by design: NVIDIA paths, real DRM-master timing,
fingerprint, and anything aesthetic — those remain hardware checks.
