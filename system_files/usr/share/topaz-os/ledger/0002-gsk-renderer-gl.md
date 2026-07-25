---
title: GTK4 defaults to the GL renderer instead of Vulkan
date: 2026-07-25
status: active
paths:
  - /usr/lib/environment.d/50-gsk-renderer.conf
---
# GTK4 defaults to the GL renderer instead of Vulkan

On hybrid AMD+NVIDIA laptops, every GTK4 application launch was taking an
extra ~2.1 seconds (measured on an RTX 4060 Max-Q) because GTK4's default
Vulkan renderer enumerates Vulkan devices at startup, and the NVIDIA Vulkan
ICD powers on a runtime-suspended dGPU just to report its capabilities —
even though the application renders on the iGPU and never uses the dGPU.

NVIDIA has acknowledged the enumeration wake-up as a driver limitation with
no committed fix (https://forums.developer.nvidia.com/t/288095; see also
https://gitlab.gnome.org/GNOME/gtk/-/issues/6689).

`GSK_RENDERER=gl` is set system-wide via environment.d. The GL path performs
no device enumeration that touches the dGPU, so it stays suspended until an
application genuinely needs it (verified: GPU remains in `suspended`
runtime status through GTK4 app launches). Applications that actually use
Vulkan or the dGPU are unaffected. Revisit if NVIDIA ships an
enumeration-without-wake fix.
