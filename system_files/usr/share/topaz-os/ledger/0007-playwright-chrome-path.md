---
title: Chrome available at /opt/google/chrome for automation tools
date: 2026-07-25
status: active
paths:
  - /usr/lib/tmpfiles.d/topaz-chrome-path.conf
  - /opt/google/chrome/chrome
---
# Chrome available at /opt/google/chrome for automation tools

Playwright (and other browser automation tooling) hardcodes the Chrome
executable path `/opt/google/chrome/chrome`. On this image Chrome is a
Flatpak, so that path does not exist naturally.

A tmpfiles.d rule recreates it on every boot as a symlink to the Flatpak
export (`/var/lib/flatpak/exports/bin/com.google.Chrome`, itself a wrapper
that runs the sandboxed Chrome). This is persistent-by-construction on an
ostree system because /opt resolves to /var/opt. If Chrome is not installed
as a system Flatpak the symlink dangles, which is harmless.

Credit for the approach: https://thenets.org/posts/playwright-mcp-flatpak-linux-new/
