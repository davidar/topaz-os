---
title: Qt Flatpak dark theme via ujust recipe
date: 2026-07-25
status: active
paths:
  - /usr/share/ublue-os/just/60-custom.just
---
# Qt Flatpak dark theme via ujust recipe

Qt6 Flatpaks on the KDE runtime (OBS, VLC, qBittorrent, ...) do not follow
GNOME dark mode: GNOME signals dark via `color-scheme` but leaves
`gtk-theme-name` at Adwaita (light), Qt platform themes read the latter, and
the KDE Flatpak platform theme does not translate the portal's dark signal
into a dark palette. QGnomePlatform is unmaintained for Qt6.

The working arrangement (found by elimination — palette overrides, portal
themes, and kdeglobals all fail in various ways): Kvantum as the widget style
with the KvGnomeDark theme, `QT_QPA_PLATFORMTHEME=gtk3` +
`GTK_THEME=Adwaita:dark` so Qt receives a dark palette, and the Kvantum
config directory exposed read-only to the sandboxes.

This is inherently per-user configuration (flatpak user overrides and files
in $HOME), so the image delivers it as an opt-in recipe rather than baked
state: `ujust topaz-qt-dark`. The recipe installs the Kvantum style for each
installed KDE runtime branch, writes the Kvantum config, and applies the
Flatpak overrides.
