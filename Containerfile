# Build contexts: scripts and system files referenced without being copied
# into the final image. One context stage per layer, because podman keys a
# RUN's cache on the whole source stage of its bind mounts — a single
# shared context would re-run the package install for any system-file
# edit.
FROM scratch AS ctx-packages
COPY build_files/install-packages.sh build_files/locked-install.lib.sh build_files/packages.lock /

FROM scratch AS ctx-niri-session
COPY build_files/install-niri-session.sh /
COPY build_files/patches /patches

FROM scratch AS ctx-files
COPY build_files/configure.sh /
COPY system_files /system_files

# chayang, the fade before the idle lock of the niri (topaz) session
# (ledger 0046), at the upstream commit Fedora packages as 0.1.0, with one
# patch from build_files/patches/: it draws its overlay from a
# single-pixel buffer, a protocol niri does not export, so unpatched it
# exits before drawing anything. The patch falls back to a 1x1 wl_shm
# buffer. Nothing in the build embeds a timestamp or a path. The builder's
# Fedora release must match the base image's (currently 44): a newer
# builder links against a newer glibc than the image ships, and the
# binary fails to load. `topaz check` asserts every fork-built binary's
# libraries resolve, so a mismatched bump fails the build, not the login.
FROM registry.fedoraproject.org/fedora:44@sha256:99741a26ce7d4ee2746a564552210f267a458c527cc09ea7dd103ecbe62b0d5a AS niri-session-build
ARG CHAYANG_REPO=https://gitlab.freedesktop.org/emersion/chayang.git
ARG CHAYANG_REF=fc98f97db88c890fb4589f3d2a090f3b0ce81f62
RUN dnf -y install gcc git-core pkgconf-pkg-config meson ninja-build \
    wayland-devel wayland-protocols-devel && dnf clean all
RUN --mount=type=bind,from=ctx-niri-session,source=/patches/chayang-shm-fallback.patch,target=/ctx/chayang-shm-fallback.patch \
    git init -q /src-chayang && \
    git -C /src-chayang fetch --depth=1 "$CHAYANG_REPO" "$CHAYANG_REF" && \
    git -C /src-chayang checkout -q FETCH_HEAD && \
    git -C /src-chayang apply /ctx/chayang-shm-fallback.patch && \
    meson setup --buildtype=release /src-chayang/build /src-chayang && \
    ninja -C /src-chayang/build && \
    install -Dm0755 /src-chayang/build/chayang /out/chayang && \
    printf 'chayang_repo=%s\nchayang_ref=%s\n' "$CHAYANG_REPO" "$CHAYANG_REF" \
        > /out/build-info

# niri itself, built from the topaz fork at a pinned commit on top of the
# upstream release Fedora packages (ledger 0037): hardcoded gesture,
# input, layout and animation constants promoted to config keys that
# hot-reload like the rest of niri's config, background effects masked by
# each surface's own alpha, a trust list for sandbox engines, and the
# ext-image-copy-capture protocols so the screenshot portal can capture.
# Same Fedora-release rule as above.
FROM registry.fedoraproject.org/fedora:44@sha256:99741a26ce7d4ee2746a564552210f267a458c527cc09ea7dd103ecbe62b0d5a AS niri-build
ARG NIRI_REPO=https://github.com/davidar/niri.git
ARG NIRI_REF=bc9985a31b4527132226249dcda664aa1c713101
RUN dnf -y install gcc cargo rust clang glibc-devel pkgconf-pkg-config \
    git-core cairo-devel dbus-devel mesa-libgbm-devel gdk-pixbuf2-devel \
    glib2-devel gtk4-devel libadwaita-devel libdisplay-info-devel \
    libinput-devel pipewire-devel libseat-devel systemd-devel pango-devel \
    wayland-devel libxkbcommon-devel && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$NIRI_REPO" "$NIRI_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    # Upstream's release profile keeps line-table debuginfo (a 160 MiB
    # binary); strip at link time like the Fedora package does.
    SOURCE_DATE_EPOCH="$(git -C /src log -1 --format=%ct)" \
    CARGO_PROFILE_RELEASE_STRIP=true \
        cargo build --release --manifest-path=/src/Cargo.toml && \
    install -Dm0755 /src/target/release/niri /out/niri && \
    printf 'niri_repo=%s\nniri_ref=%s\n' "$NIRI_REPO" "$NIRI_REF" > /out/build-info

# caustics, the bar and the canvas of the niri (topaz) session (ledgers
# 0044, 0049), built at a pinned commit of https://github.com/davidar/caustics.
# The two hosts and their sidecars, sixteen binaries, are one set, installed
# under a directory named by the ABI hash the bar prints, as the project's
# own install script lays them out (its BINARIES list is the authoritative
# one; the shaders are compiled in, no sources ship). The build script
# fetches the Slang release the bindings were generated against and checks
# it against the SHA-256 recorded in the crate, so that download is as
# pinned as a crate's.
FROM registry.fedoraproject.org/fedora:44@sha256:99741a26ce7d4ee2746a564552210f267a458c527cc09ea7dd103ecbe62b0d5a AS caustics-build
ARG CAUSTICS_REPO=https://github.com/davidar/caustics.git
ARG CAUSTICS_REF=2924bb830a390aefe8ca02f11d34b8fc80babdef
RUN dnf -y install gcc cargo rust git-core pkgconf-pkg-config && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$CAUSTICS_REPO" "$CAUSTICS_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    SOURCE_DATE_EPOCH="$(git -C /src log -1 --format=%ct)" \
    CARGO_PROFILE_RELEASE_STRIP=true \
        cargo build --release --workspace --manifest-path=/src/Cargo.toml && \
    set_hash="$(/src/target/release/caustics-bar --abi-hash)" && \
    [ "${#set_hash}" -eq 16 ] && \
    for b in caustics-bar caustics-sysmon caustics-tray caustics-power caustics-audio \
             caustics-network caustics-bluetooth caustics-notify caustics-apps \
             caustics-glyphs caustics-reload caustics-canvas caustics-wallpaper \
             caustics-canvasctl caustics-polkit caustics-lock; do \
        install -Dm0755 "/src/target/release/$b" "/out/lib/caustics-bar/$set_hash/$b" || exit 1; \
    done && \
    printf 'caustics_repo=%s\ncaustics_ref=%s\ncaustics_set=%s\n' \
        "$CAUSTICS_REPO" "$CAUSTICS_REF" "$set_hash" > /out/build-info

# Base: Bluefin DX with NVIDIA open kernel modules
FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:latest@sha256:37285c460a1648fed27f1265e1658b0285c5c9a1709d3543cd81a935c0f71bdb

# The image ships as ordinary content-keyed OCI layers — no rechunking.
# Each RUN below is one layer, ordered least- to most-frequently changing,
# and mounts only the inputs it is keyed on, so an edit invalidates (and a
# machine re-downloads) only the layers whose inputs actually changed:
# each package layer moves on its own lock change, the compositor layer on
# a fork bump, and everything topaz-authored rides in a kilobyte-sized
# tail layer. Builds pass --timestamp 0 (Justfile) so layer file timestamps
# never churn a digest — the same canonicalization ostree applies on
# deployment anyway.

# Locked package set (ledger 0022), plus everything derived purely
# from it: nethogs capabilities, reproducibility fixups, /var scrub.
RUN --mount=type=bind,from=ctx-packages,source=/install-packages.sh,target=/ctx/install-packages.sh \
    --mount=type=bind,from=ctx-packages,source=/locked-install.lib.sh,target=/ctx/locked-install.lib.sh \
    --mount=type=bind,from=ctx-packages,source=/packages.lock,target=/ctx/packages.lock \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/install-packages.sh

# chayang from the niri-session-build stage (ledger 0046), the fork-built
# niri from the niri-build stage (ledger 0037) and the caustics set, bar
# and canvas, from the caustics-build stage (ledgers 0044, 0049)
RUN --mount=type=bind,from=ctx-niri-session,source=/install-niri-session.sh,target=/ctx/install-niri-session.sh \
    --mount=type=bind,from=niri-session-build,source=/out,target=/niri-session \
    --mount=type=bind,from=niri-build,source=/out,target=/niri-build \
    --mount=type=bind,from=caustics-build,source=/out,target=/caustics-build \
    /ctx/install-niri-session.sh

# topaz system files and configuration on top of the installed set
RUN --mount=type=bind,from=ctx-files,source=/configure.sh,target=/ctx/configure.sh \
    --mount=type=bind,from=ctx-files,source=/system_files,target=/ctx/system_files \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/configure.sh

# Verify final image and contents are correct, and that the image still
# matches the claims in its provenance ledger. Lint warnings are fatal:
# stray /var and /run content is exactly the build debris that made
# rebuilds nondeterministic (ledger 0024), so new debris fails the build.
# The sidecar assertion holds because the databases are in DELETE journal
# mode (ledger 0020) — the check's own rpm queries no longer create them.
# One RUN: anything a gate command created would die in this same layer.
# The rmdir first: buildah sometimes commits the /ctx bind-mount target
# directory left over from the earlier steps (empty, harmless, but it
# flips layer digests build-to-build); this step has no ctx mount, so the
# leak can be cleaned here. rmdir only — if /ctx somehow has content,
# something wrote through a mount and the check below fails the build.
RUN { rmdir /ctx 2>/dev/null || true; } && \
    /usr/bin/topaz check && \
    bootc container lint --fatal-warnings && \
    bash -c 'shopt -s nullglob; \
             sidecars=(/usr/share/rpm/*.sqlite-{wal,shm} \
                       /usr/lib/sysimage/libdnf5/*.sqlite-{wal,shm}); \
             [ ${#sidecars[@]} -eq 0 ]'
