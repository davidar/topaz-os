# topaz-os

A custom [bootc](https://github.com/bootc-dev/bootc) image based on
[Bluefin DX](https://projectbluefin.io/) (NVIDIA open-kernel-module variant), adding a
[niri](https://github.com/YaLTeR/niri) session with the
[caustics](https://github.com/davidar/caustics) bar and a few quality-of-life fixes for
hybrid AMD+NVIDIA laptops. Built from the Universal Blue
[image-template](https://github.com/ublue-os/image-template).

## What's different from Bluefin DX

Every deliberate deviation from the base image is recorded in a provenance ledger
shipped inside the image (`/usr/share/topaz-os/ledger/`) — what changed, why, and the
evidence — and `topaz check` verifies the deviations at build time, so an image that no
longer matches its own ledger fails to build. The ledger, not this README, is the
authoritative list:

```
$ topaz ledger                        # list all recorded deviations
$ topaz why /usr/lib/environment.d/50-gsk-renderer.conf   # why does this file deviate?
$ topaz check                         # verify the deviations actually hold
```

In broad strokes:

- **niri (topaz) session** — the [niri](https://github.com/YaLTeR/niri)
  scrollable-tiling compositor's own systemd session with the
  [caustics](https://github.com/davidar/caustics) bar (panel, dock, tray, notifications,
  all drawn on the GPU), its canvas for the wallpaper (the base image's day/night
  schedule, cross-faded), the dim before the idle lock, the polkit prompt and the
  lock screen, and toolkit-free tools (swayidle, fuzzel) for the rest; no COSMIC
  shell process. The idle timeouts are knobs in one file, `~/.config/topaz/session.conf`.
  niri is built from source with every hardcoded gesture, input, layout and animation
  constant promoted to config and blur masked by each surface's own shape.
- **No COSMIC session** — the COSMIC desktop the image started with is gone with the
  forks it needed (ledger 0047); the COSMIC apps stay as plain Fedora packages,
  nothing COSMIC runs in the session (ledgers 0039, 0050). GNOME remains the fallback session — pick at
  the login screen (greetd running tuigreet on the console; ledger 0045).
- **Hybrid-laptop fixes** — keep the dGPU asleep (`GSK_RENDERER=gl`), avoid amdgpu
  PSR/DDC wedges that freeze the desktop, supergfxd for GPU mode switching, Goodix
  fingerprint support with fingerprint-friendly PAM and fingerprint unlock at the lock screen.
- **No memory-thrash lockups** — MGLRU `min_ttl_ms` (ChromeOS's policy) kills runaway
  allocations in ~1s instead of thrashing; SysRq enabled as the manual escape hatch.
- **Swap reaches the disk** — zswap compresses cold pages in RAM and drains the oldest
  to a swapfile the image creates on first boot; Fedora's RAM-only zram is retired.
- **Supply-chain hygiene** — the build installs exactly the NEVRAs in
  `build_files/packages.lock` (koji backfills builds the mirrors dropped), rebuilds are
  byte-reproducible, and images are signed with [cosign](https://github.com/sigstore/cosign).
- **Opt-in extras** — the `topaz dev` transient-overlay workflow for daily-driving
  locally built binaries, `topaz pull` for parallel partial-pull updates staged
  nightly ahead of uupd (bootc pulls serially until bootc#20), and `ujust topaz-home` to fetch
  [topaz-home](https://github.com/davidar/topaz-home), the userland companion repo
  (night-shift triage, desktop services and fixes) that updates at git speed instead
  of being baked into the image.

## Usage

```bash
sudo bootc switch quay.io/davidar/topaz-os:latest
systemctl reboot
```

Images are built in CI on every push and signed with cosign (the public key is in this
repository, `cosign.pub`). The published image is split into content-based layers with
[chunkah](https://github.com/coreos/chunkah) — roughly one per package — and
compressed zstd:chunked, so updates download only the files that actually changed
(a real update measured 36 MiB where serial bootc re-fetched 2.5 GiB). Builds are byte-reproducible; a
weekly scheduled job rebuilds the unchanged tree and fails if the result diverges from
the published image by even one layer.

## Notes

- This is a personal image tuned for one person's hardware. Everything here is
  reproducible from the `Containerfile` and the scripts in `build_files/` — fork and
  adjust rather than consuming directly if your hardware differs.
- The base image does all the heavy lifting; see the
  [Bluefin documentation](https://docs.projectbluefin.io/) for everything it provides.
