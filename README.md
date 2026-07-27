# topaz-os

A custom [bootc](https://github.com/bootc-dev/bootc) image based on
[Bluefin DX](https://projectbluefin.io/) (NVIDIA open-kernel-module variant), adding the
[COSMIC desktop](https://system76.com/cosmic) and a few quality-of-life fixes for hybrid
AMD+NVIDIA laptops. Built from the Universal Blue
[image-template](https://github.com/ublue-os/image-template).

## What's added on top of Bluefin DX

- **Identifies as topaz-os** — `NAME`/`PRETTY_NAME` rebranded in `os-release` so GRUB
  can tell this image apart from its Bluefin rollback; all machine-readable fields stay
  Bluefin's for tooling compatibility.
- **COSMIC desktop (1.4.x, from the Fedora repos)** — installed alongside GNOME; pick
  your session at the GDM login screen. `cosmic-greeter` comes along as a hard
  dependency of `cosmic-session` but is not enabled: GDM remains the display
  manager (verified by `topaz check`).
- **No passwordless i2c (DDC/CI) access** — the ddcutil and OpenRGB `uaccess` udev
  rules are removed: cosmic-settings-daemon's blind monitor probing otherwise wedges
  amdgpu PSR arming and freezes COSMIC (ledger 0013). `sudo ddcutil` still works.
- **`GSK_RENDERER=gl` system-wide** — GTK4's default Vulkan renderer makes the NVIDIA
  Vulkan ICD enumerate devices at startup, which wakes a runtime-suspended dGPU and adds
  ~2 seconds to every GTK4 app launch on hybrid laptops
  ([upstream report](https://forums.developer.nvidia.com/t/288095)). The GL renderer
  avoids the wake entirely, letting the dGPU stay asleep until something actually needs it.
- **Goodix fingerprint reader support (27c6:550a)** — `libfprint` swapped for
  `libfprint-tod` + the Goodix TOD driver
  (COPR: [antiderivative/libfprint-tod-goodix-0.0.9](https://copr.fedorainfracloud.org/coprs/antiderivative/libfprint-tod-goodix-0.0.9/)).
  Found on the Lenovo Legion Slim 5 14APH8 and various other laptops.
- **earlyoom, enabled by default** — with a swap-usage threshold added to the Fedora
  defaults so memory-pressure intervention happens before swap thrashing makes the
  desktop unresponsive.
- **Fingerprint-friendly PAM** — custom authselect profile (generated at build
  time from the base profile, with a 5s fprintd timeout patched into
  `system-auth`) so the password prompt isn't blocked for 30s when fingerprint
  auth is enrolled.
- **`/opt/google/chrome/chrome`** recreated at boot as a symlink to the Chrome Flatpak
  export (tmpfiles.d), so Playwright and similar tools find Chrome at their hardcoded path.
- **supergfxd enabled** by preset for GPU mode switching on hybrid laptops.
- **speech-dispatcher socket enabled** for user sessions, fixing text-to-speech in
  Flatpak browsers out of the box.
- **`ujust topaz-qt-dark`** — opt-in recipe making Qt Flatpaks on the KDE runtime follow
  GNOME dark mode (Kvantum + platform-theme arrangement, applied per user).
- **Opt-in user-setup recipes** — `ujust topaz-{tailscale-tray,wallpaper,dropbox,
  electron-wayland,chrome-integration,claude-desktop,kitty}`; helpers ship inert in
  the image (ledger 0016) and nothing runs until invoked.
- **A provenance ledger** — every deliberate deviation from the base image has an
  entry under `/usr/share/topaz-os/ledger/` recording what changed, why, and the
  evidence. Query it with the included `topaz` CLI:

  ```
  $ topaz why /etc/default/earlyoom     # why does this file deviate?
  $ topaz ledger                        # list all recorded deviations
  $ topaz check                         # verify the deviations actually hold
  ```

  `topaz check` also runs at image build time, so an image that no longer
  matches its own ledger fails to build.
- **cosmic-comp from the [topaz fork](https://github.com/davidar/cosmic-comp)** —
  workspace-swipe finger count, physics, and rubber-band edge bounce are
  hot-reloadable config (pinned commit, built from source; pending upstream).
- **`topaz dev`** — transient `/usr` overlay workflow (`bootc usroverlay`) for
  daily-driving locally built binaries; a reboot restores the signed image, and
  `topaz check` loudly reports any active overlay.
- **An opt-in "night shift"** — a daily systemd user timer that digests system
  events (failed units, journal errors, OOM activity, staged updates, the
  self-check) into a morning report. Analysis is a pluggable hook: point
  `TRIAGE_CMD` at any command that reads the digest on stdin — an AI agent, a
  local model, or a script — or leave it unset for raw digests. Disabled by
  default; `topaz nightshift enable` to opt in. See
  `/usr/share/topaz-os/nightshift.conf.example`.

## Usage

```bash
sudo bootc switch ghcr.io/davidar/topaz-os:latest
systemctl reboot
```

Images are built daily against the latest Bluefin DX stable and signed with
[cosign](https://github.com/sigstore/cosign); the public key is in this repository
(`cosign.pub`).

## Notes

- This is a personal image tuned for one person's hardware. Everything here is
  reproducible from the `Containerfile` and `build_files/build.sh` — fork and adjust
  rather than consuming directly if your hardware differs.
- The base image does all the heavy lifting; see the
  [Bluefin documentation](https://docs.projectbluefin.io/) for everything it provides.
