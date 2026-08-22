# Build contexts: scripts and system files referenced without being copied
# into the final image. One context stage per layer, because podman keys a
# RUN's cache on the whole source stage of its bind mounts — a single
# shared context would re-run the package install for any system-file
# edit.
FROM scratch AS ctx-packages
COPY build_files/install-packages.sh build_files/locked-install.lib.sh build_files/packages.lock /

FROM scratch AS ctx-comp
COPY build_files/install-comp.sh /

FROM scratch AS ctx-greeter
COPY build_files/install-greeter.sh /

FROM scratch AS ctx-niri-session
COPY build_files/install-niri-session.sh /

FROM scratch AS ctx-files
COPY build_files/configure.sh /
COPY system_files /system_files

# Compositor fork: cosmic-comp with config-driven workspace gestures, built
# at a pinned commit of github.com/davidar/cosmic-comp (ledger 0015).
# The builder's Fedora release must match the base image's (currently 44):
# a newer builder links the binary against a newer glibc than the image
# ships, and the compositor fails to load at session start. `topaz check`
# asserts the binary's libraries resolve, so a mismatched bump fails the
# build rather than the login.
FROM registry.fedoraproject.org/fedora:44@sha256:754c6d7d5767750e57caf10376a72eb347ce5721a4310334aaeedb09ba80e05f AS comp-build
ARG COSMIC_COMP_REPO=https://github.com/davidar/cosmic-comp.git
ARG COSMIC_COMP_REF=864aadb0adfc6a1421fef6f2fc427adbffd21b38
RUN dnf -y install gcc cargo rust pkgconf-pkg-config git-core \
    libseat-devel libinput-devel systemd-devel mesa-libgbm-devel \
    libxkbcommon-devel pixman-devel wayland-devel libglvnd-devel \
    libdisplay-info-devel fontconfig-devel clang-libs && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$COSMIC_COMP_REPO" "$COSMIC_COMP_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    # SOURCE_DATE_EPOCH = commit time: rust-embed bakes the i18n files'
    # created/modified timestamps into the binary (it honors this variable,
    # overriding both), so checkout-time stamps would make every build unique
    # and churn the image's compositor chunk on otherwise no-op rebuilds.
    # With this, the same REF + toolchain reproduces bit-identically.
    SOURCE_DATE_EPOCH="$(git -C /src log -1 --format=%ct)" \
        cargo build --release --manifest-path=/src/Cargo.toml && \
    install -Dm0755 /src/target/release/cosmic-comp /out/cosmic-comp && \
    printf 'repo=%s\nref=%s\n' "$COSMIC_COMP_REPO" "$COSMIC_COMP_REF" \
        > /out/fork-info

# Greeter fork: cosmic-greeter with JXL wallpaper decoding and fingerprint
# re-arm on wake, built at a pinned commit of
# github.com/davidar/cosmic-greeter (ledger 0034). Same Fedora-release rule
# as comp-build above: the builder must track the base image's release or
# the binary links a glibc the image does not ship.
FROM registry.fedoraproject.org/fedora:44@sha256:754c6d7d5767750e57caf10376a72eb347ce5721a4310334aaeedb09ba80e05f AS greeter-build
ARG COSMIC_GREETER_REPO=https://github.com/davidar/cosmic-greeter.git
ARG COSMIC_GREETER_REF=9918b062a8c90a269a42d1dda056a48cf140d7c8
RUN dnf -y install gcc cargo rust pkgconf-pkg-config git-core \
    pam-devel clang clang-devel systemd-devel mesa-libgbm-devel \
    libinput-devel libxkbcommon-devel wayland-devel libglvnd-devel \
    fontconfig-devel clang-libs && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$COSMIC_GREETER_REPO" "$COSMIC_GREETER_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    # SOURCE_DATE_EPOCH = commit time: cosmic-greeter embeds its i18n files
    # with rust-embed just like cosmic-comp (see comp-build above), so
    # checkout-time stamps would make every build unique.
    SOURCE_DATE_EPOCH="$(git -C /src log -1 --format=%ct)" \
        cargo build --release --manifest-path=/src/Cargo.toml \
        --bin cosmic-greeter && \
    install -Dm0755 /src/target/release/cosmic-greeter /out/cosmic-greeter && \
    printf 'repo=%s\nref=%s\n' "$COSMIC_GREETER_REPO" "$COSMIC_GREETER_REF" \
        > /out/fork-info

# niri session: the two small binaries the alternative "COSMIC on niri"
# session needs beyond its packaged parts (ledger 0035) —
# cosmic-ext-alternative-startup, the shim that hands niri's sockets back
# to cosmic-session, and cosmic-idle built from the topaz fork, which
# makes wlr-output-power-management and single-pixel-buffer optional
# (niri implements neither and the packaged binary aborts at startup
# without them, leaving the session with no idle lock or suspend). Same
# Fedora-release rule as the stages above: the builder must track the
# base image's release.
FROM registry.fedoraproject.org/fedora:44@sha256:754c6d7d5767750e57caf10376a72eb347ce5721a4310334aaeedb09ba80e05f AS niri-session-build
ARG COSMIC_ALT_STARTUP_REPO=https://github.com/Drakulix/cosmic-ext-alternative-startup.git
ARG COSMIC_ALT_STARTUP_REF=8ceda00197c7ec0905cf1dccdc2d67d738e45417
ARG COSMIC_IDLE_REPO=https://github.com/davidar/cosmic-idle.git
ARG COSMIC_IDLE_REF=6e0e1c50fb3bc4e45fc8c998dc9c00772fed8435
RUN dnf -y install gcc cargo rust pkgconf-pkg-config git-core \
    clang clang-devel systemd-devel mesa-libgbm-devel \
    libinput-devel libxkbcommon-devel wayland-devel libglvnd-devel \
    fontconfig-devel clang-libs && dnf clean all
# SOURCE_DATE_EPOCH = commit time on both builds, for the same reason as
# the stages above: nothing here may bake a checkout-time stamp into a
# binary and churn the layer on an otherwise no-op rebuild.
RUN git init -q /src-startup && \
    git -C /src-startup fetch --depth=1 "$COSMIC_ALT_STARTUP_REPO" "$COSMIC_ALT_STARTUP_REF" && \
    git -C /src-startup checkout -q FETCH_HEAD && \
    SOURCE_DATE_EPOCH="$(git -C /src-startup log -1 --format=%ct)" \
        cargo build --release --manifest-path=/src-startup/Cargo.toml && \
    install -Dm0755 /src-startup/target/release/cosmic-ext-alternative-startup \
        /out/cosmic-ext-alternative-startup
RUN git init -q /src-idle && \
    git -C /src-idle fetch --depth=1 "$COSMIC_IDLE_REPO" "$COSMIC_IDLE_REF" && \
    git -C /src-idle checkout -q FETCH_HEAD && \
    SOURCE_DATE_EPOCH="$(git -C /src-idle log -1 --format=%ct)" \
        cargo build --release --manifest-path=/src-idle/Cargo.toml && \
    install -Dm0755 /src-idle/target/release/cosmic-idle /out/cosmic-idle && \
    printf 'startup_repo=%s\nstartup_ref=%s\nidle_repo=%s\nidle_ref=%s\n' \
        "$COSMIC_ALT_STARTUP_REPO" "$COSMIC_ALT_STARTUP_REF" \
        "$COSMIC_IDLE_REPO" "$COSMIC_IDLE_REF" \
        > /out/build-info

# niri itself, built from the topaz fork at a pinned commit on top of the
# upstream release Fedora packages (ledger 0037): hardcoded gesture,
# input, layout and animation constants promoted to config keys that
# hot-reload like the rest of niri's config, background effects masked by
# each surface's own alpha, and a trust list for sandbox engines so the
# panel's applets see the window list. Same Fedora-release rule as above.
FROM registry.fedoraproject.org/fedora:44@sha256:754c6d7d5767750e57caf10376a72eb347ce5721a4310334aaeedb09ba80e05f AS niri-build
ARG NIRI_REPO=https://github.com/davidar/niri.git
ARG NIRI_REF=21f6928f306c9e2319b0818b46409622f7f90b80
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

# cosmic-applets built from the topaz fork at a pinned commit on top of
# the upstream commit Fedora packages (ledger 0038): the dock
# (cosmic-app-list) and the minimize applet abort at startup without
# cosmic-comp's zcosmic toplevel manager. The fork lists windows through
# ext-foreign-toplevel-list and acts on them through
# wlr-foreign-toplevel-management when the zcosmic manager is absent;
# under cosmic-comp the original path runs unchanged.
FROM registry.fedoraproject.org/fedora:44@sha256:754c6d7d5767750e57caf10376a72eb347ce5721a4310334aaeedb09ba80e05f AS cosmic-applets-build
ARG COSMIC_APPLETS_REPO=https://github.com/davidar/cosmic-applets.git
ARG COSMIC_APPLETS_REF=05afaaa7493f47d4c1de4afc3da3142353675d7c
RUN dnf -y install gcc cargo rust clang glibc-devel pkgconf-pkg-config \
    git-core just libxkbcommon-devel wayland-devel mesa-libEGL-devel \
    mesa-libGL-devel fontconfig-devel freetype-devel dbus-devel \
    pulseaudio-libs-devel pipewire-devel libinput-devel systemd-devel \
    expat-devel openssl-devel lld && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$COSMIC_APPLETS_REPO" "$COSMIC_APPLETS_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    SOURCE_DATE_EPOCH="$(git -C /src log -1 --format=%ct)" \
    CARGO_PROFILE_RELEASE_STRIP=true \
        cargo build --release --manifest-path=/src/Cargo.toml -p cosmic-applets && \
    install -Dm0755 /src/target/release/cosmic-applets /out/cosmic-applets && \
    printf 'applets_repo=%s\napplets_ref=%s\n' "$COSMIC_APPLETS_REPO" "$COSMIC_APPLETS_REF" > /out/build-info

# Base: Bluefin DX with NVIDIA open kernel modules
FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable@sha256:6a1b8c50515e2dbebe2eb09e7807bb859a06137910ef9f92aaf97b0feaec3940

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

# Forked cosmic-comp from the comp-build stage (ledger 0015)
RUN --mount=type=bind,from=ctx-comp,source=/install-comp.sh,target=/ctx/install-comp.sh \
    --mount=type=bind,from=comp-build,source=/out,target=/comp \
    /ctx/install-comp.sh

# Forked cosmic-greeter from the greeter-build stage (ledger 0034)
RUN --mount=type=bind,from=ctx-greeter,source=/install-greeter.sh,target=/ctx/install-greeter.sh \
    --mount=type=bind,from=greeter-build,source=/out,target=/greeter \
    /ctx/install-greeter.sh

# niri-session binaries from the niri-session-build stage (ledger 0035),
# the fork-built niri from the niri-build stage (ledger 0037) and the
# fork-built applets from the cosmic-applets-build stage (ledger 0038)
RUN --mount=type=bind,from=ctx-niri-session,source=/install-niri-session.sh,target=/ctx/install-niri-session.sh \
    --mount=type=bind,from=niri-session-build,source=/out,target=/niri-session \
    --mount=type=bind,from=niri-build,source=/out,target=/niri-build \
    --mount=type=bind,from=cosmic-applets-build,source=/out,target=/cosmic-applets-build \
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
