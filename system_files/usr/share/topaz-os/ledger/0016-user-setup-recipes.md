---
title: Opt-in user-setup recipes and their helpers
date: 2026-07-27
status: active
paths:
  - /usr/share/ublue-os/just/60-custom.just
  - /usr/lib/systemd/user/tailscale-systray.service
  - /usr/lib/systemd/user/topaz-dropbox.service
  - /usr/lib/systemd/user/topaz-bluefin-wallpaper.service
  - /usr/lib/systemd/user/topaz-bluefin-wallpaper.timer
  - /usr/libexec/topaz-dropbox-icons
  - /usr/bin/topaz-bluefin-wallpaper
  - /usr/bin/topaz-claude-desktop-update
---
# Opt-in user-setup recipes and their helpers

Per-user configuration never ships as baked user state; it ships as `ujust`
recipes the user invokes deliberately (the base image's `60-custom.just`
hook). This entry covers the recipe pack and the inert helper files it
relies on — units and scripts under `/usr` that do nothing until a recipe
enables them:

- **topaz-tailscale-tray** — enables a user unit running `tailscale
  systray` (ships with tailscale; native StatusNotifier).
- **topaz-wallpaper** — enables a timer that keeps COSMIC's wallpaper on
  Bluefin's monthly artwork, flipping day/night variants at the midpoints
  of the GNOME timed-XML transitions (04:40 / 17:50) and rolling the month
  at 00:05. COSMIC has no timed-wallpaper support of its own; the script
  points cosmic-config at the image's own jxl files, so new art arrives
  with image updates.
- **topaz-dropbox** — installs the Dropbox Flatpak and enables a launcher
  unit. Two hard-won fixes are encoded: the unit is `oneshot` because
  `dropbox start` hands the daemon to the Flatpak session helper and
  exits (the daemon lives outside the unit's cgroup — restarts need
  `flatpak kill`), and a helper syncs the sandbox-private tray icons into
  the user icon theme, without which COSMIC's panel renders a
  missing-image placeholder (the Flatpak advertises an IconThemePath the
  host cannot read).
- **topaz-electron-wayland** — per-app `ELECTRON_OZONE_PLATFORM_HINT=auto`
  Flatpak overrides. Electron apps default to XWayland, and image pastes
  into them cross the compositor's X11 selection bridge, which drops
  large transfers (Discord's "file cannot be empty"); Wayland-native
  avoids the bridge entirely.
- **topaz-chrome-integration** — Chrome Flatpak overrides for automation
  workflows: WebGPU via Vulkan, plus read-only visibility of Claude Code
  state for browser-extension use.
- **topaz-claude-desktop** — rootless installer/updater for the Debian-only
  Claude Desktop package, extracted into `~/.local` (no layering, no root
  beyond the chrome-sandbox setuid fixup it prompts for).
- **topaz-qt-dark** — see ledger 0011; gained a `--nofilesystem=
  xdg-config/kdeglobals` negation so KDE-runtime apps cannot read a host
  kdeglobals that fights the Kvantum theme.
- **topaz-kitty** — kitty via the official user-scoped installer with
  desktop integration.
- **topaz-touchpad-dwt** (added 2026-07-29) — sets
  `disable_while_typing: Some(false)` in cosmic-comp's `input_touchpad`
  config (hot-applied). libinput's disable-while-typing guards against
  palm brushes, but it also makes keyboard-plus-touchpad play (FPS
  controls) impossible; opt out per user, `enabled=true` restores it.

The image never runs any of this automatically; `topaz check` asserts the
helper files exist and parse.
