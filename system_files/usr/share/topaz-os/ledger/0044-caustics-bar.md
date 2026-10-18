---
title: The caustics bar, built from source and installed as one set
date: 2026-10-17
status: active
paths:
  - /usr/lib/caustics-bar
  - /usr/bin/caustics-bar
  - /usr/lib/systemd/user/caustics-bar.service
  - /usr/libexec/topaz/caustics-bar
  - /usr/share/topaz-os/niri-session-build
---
# The caustics bar, built from source and installed as one set

The niri (topaz) session's panel (ledger 0041) is
[caustics](https://github.com/davidar/caustics): a status bar whose
layout, text and drawing run in Slang compute shaders on the GPU, with a
small bar process owning the Wayland surface and a set of sidecar
processes talking to the rest of the system. It provides the dock with
window previews, the system tray, charts, a clock and calendar, the
notification daemon, the volume and brightness toasts, and menus for
power, audio, network and Bluetooth.
No distribution packages it, so the image builds it (Containerfile
`caustics-build` stage) at a pinned commit.

The install follows the project's own layout. The bar and its ten
sidecars are one **set**: the eleven binaries live under
`/usr/lib/caustics-bar/<abi-hash>/`, named by the hash of the contract
between them that the bar prints with `--abi-hash`, and
`/usr/bin/caustics-bar` is a symlink into that directory. The bar
resolves its own path and starts the sidecars beside it, and refuses a
sidecar from another set, so there is no way to run half a set. The
shaders are compiled into the binaries; the image ships no sources and
the unit sets no `CAUSTICS_DIR`, so the reload sidecar idles. A checkout
installed under `~/.local` brings its own unit, which replaces this one
by name and points the variable at the working tree.

Build inputs: Rust crates by `Cargo.lock`, git dependencies by commit,
and the Slang release the bindings were generated against, which the
build script downloads and checks against the SHA-256 recorded in the
crate. The binaries link only the C library; the Vulkan loader and the
drivers are loaded at run time from the image's mesa and NVIDIA
packages.

`/usr/libexec/topaz/caustics-bar`, the unit's ExecStart, exists for the
hybrid laptop: the Vulkan loader enumerates every installed driver, and
enumerating the discrete GPU's driver alone can wake it for the life of
the session. When an integrated GPU (amdgpu, i915, xe) is bound to a
render node, the wrapper pins `VK_DRIVER_FILES` to its driver, so the
discrete one is never opened; with no integrated GPU (a desktop, the
test VM, which draws with lavapipe) the loader is left alone, and a
`VK_DRIVER_FILES` already in the environment wins. The unit restarts the
bar on a crash within a second but not on exit 2 (the bar refusing to
run: only a discrete NVIDIA adapter, or another bar on its edge) or
exit 3 (the GPU device gone), which trying again would not improve.

`/usr/share/topaz-os/niri-session-build` records the pinned commit and
the set's hash. `topaz check` asserts exactly one set is installed, the
link resolves into it, the bar's `--abi-hash` matches the directory and
the record, all eleven binaries are present with their libraries
resolving, no shader directory or `CAUSTICS_DIR` is shipped, the unit
carries the wrapper and the exit-status rule, and the integrated-GPU and
lavapipe drivers the wrapper and the VM depend on are installed.
