# topaz-os

A custom [bootc](https://github.com/bootc-dev/bootc) image based on
[Bluefin DX](https://projectbluefin.io/) (NVIDIA open-kernel-module variant), adding the
[COSMIC desktop](https://system76.com/cosmic) and a few quality-of-life fixes for hybrid
AMD+NVIDIA laptops. Built from the Universal Blue
[image-template](https://github.com/ublue-os/image-template).

## What's different from Bluefin DX

Every deliberate deviation from the base image is recorded in a provenance ledger
shipped inside the image (`/usr/share/topaz-os/ledger/`) — what changed, why, and the
evidence — and `topaz check` verifies the deviations at build time, so an image that no
longer matches its own ledger fails to build. The ledger, not this README, is the
authoritative list:

```
$ topaz ledger                        # list all recorded deviations
$ topaz why /etc/default/earlyoom     # why does this file deviate?
$ topaz check                         # verify the deviations actually hold
```

In broad strokes:

- **COSMIC desktop** (Fedora packages) alongside the base image's GNOME — pick your
  session at the GDM login screen. cosmic-comp comes from the
  [topaz fork](https://github.com/davidar/cosmic-comp): hot-reloadable workspace-gesture
  and physics config, pending upstream.
- **Hybrid-laptop fixes** — keep the dGPU asleep (`GSK_RENDERER=gl`), avoid amdgpu
  PSR/DDC wedges that freeze the desktop, supergfxd for GPU mode switching, Goodix
  fingerprint support with fingerprint-friendly PAM and COSMIC lock-screen unlock.
- **Supply-chain hygiene** — the build installs exactly the NEVRAs in
  `build_files/packages.lock` (koji backfills builds the mirrors dropped), rebuilds are
  byte-reproducible, and images are signed with [cosign](https://github.com/sigstore/cosign).
- **Opt-in extras** — `ujust topaz-*` user-setup recipes (inert until invoked), the
  `topaz dev` transient-overlay workflow for daily-driving locally built binaries, and
  an opt-in "night shift": a daily user timer that digests system events into a morning
  report through a pluggable `TRIAGE_CMD` hook (AI agent, local model, or plain script —
  your choice; see `/usr/share/topaz-os/nightshift.conf.example`).

## Usage

```bash
sudo bootc switch ghcr.io/davidar/topaz-os:latest
systemctl reboot
```

Images are built in CI on every push and signed with cosign (the public key is in this
repository, `cosign.pub`). The image is ordinary content-keyed OCI layers (packages,
compositor, config), so updates only download the layers whose inputs changed. Builds
are byte-reproducible; a weekly scheduled job rebuilds the unchanged tree and fails if
the result diverges from the published image by even one layer.

## Notes

- This is a personal image tuned for one person's hardware. Everything here is
  reproducible from the `Containerfile` and the scripts in `build_files/` — fork and
  adjust rather than consuming directly if your hardware differs.
- The base image does all the heavy lifting; see the
  [Bluefin documentation](https://docs.projectbluefin.io/) for everything it provides.
