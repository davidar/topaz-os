---
title: supergfxd enabled by preset
date: 2026-07-25
status: active
paths:
  - /usr/lib/systemd/system-preset/45-topaz.preset
  - /usr/lib/systemd/system/supergfxd.service
---
# supergfxd enabled by preset

supergfxd provides GPU mode switching (Hybrid / Integrated / etc.) on hybrid
laptops, used via `supergfxctl` and the GNOME "GPU Supergfxctl Switch"
extension. The package ships in the base image but its service was enabled
manually on the original machine — state that would be lost on a fresh
install of this image.

A systemd preset (and an explicit enable at build time) makes the guarantee
part of the image instead of inherited machine state.
