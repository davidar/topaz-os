---
title: KDE Connect baked in (phone integration with SMS)
date: 2026-07-28
status: active
paths:
  - /usr/bin/kdeconnectd
  - /usr/bin/kdeconnect-sms
  - /etc/firewalld/zones/FedoraWorkstation.xml
---
# KDE Connect baked in (phone integration with SMS)

Fedora's `kde-connect` package (26.04.x) is installed, and the `kdeconnect`
firewalld service (TCP/UDP 1714-1764, definition shipped by firewalld
itself) is opened in the default `FedoraWorkstation` zone so device pairing
works without manual firewall surgery.

Why this and not a Flatpak: Flathub carries neither KDE Connect nor Valent.
Valent (the GNOME-native implementation, installed from the author's own
repository) was evaluated and rejected for daily use — it has no SMS UI,
which was the deciding feature. Fedora's KDE Connect ships the full app
set: daemon, settings module, and the SMS messenger.

The daemon is user-session software with no enabled system units; nothing
runs until a desktop session starts it (or the user launches the apps), so
the deviation is inert for users who ignore it, matching the image's
opt-in convention.
