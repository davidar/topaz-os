# Build contexts: scripts and system files referenced without being copied
# into the final image. One context stage per layer, because podman keys a
# RUN's cache on the whole source stage of its bind mounts — a single
# shared context would re-run the package install for any system-file
# edit.
FROM scratch AS ctx-packages
COPY build_files/install-packages.sh build_files/packages.lock /

FROM scratch AS ctx-comp
COPY build_files/install-comp.sh /

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
ARG COSMIC_COMP_REF=4d86252b4d28a81662c697e255cfa442a07ee1a0
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

# Base: Bluefin DX with NVIDIA open kernel modules
FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable@sha256:effbd5225119adb6d95202eb45b980b5fba6f57170d2158f6b8e3d17559f0489

# The image ships as ordinary content-keyed OCI layers — no rechunking.
# Each RUN below is one layer, ordered least- to most-frequently changing,
# and mounts only the inputs it is keyed on, so an edit invalidates (and a
# machine re-downloads) only the layers whose inputs actually changed: the
# package layer moves on a lock change, the compositor layer on a fork
# bump, and everything topaz-authored rides in a kilobyte-sized tail
# layer. Builds pass --timestamp 0 (Justfile) so layer file timestamps
# never churn a digest — the same canonicalization ostree applies on
# deployment anyway.

# Locked package set (ledger 0022), plus everything derived purely from
# it: nethogs capabilities, reproducibility fixups, /var scrub.
RUN --mount=type=bind,from=ctx-packages,source=/install-packages.sh,target=/ctx/install-packages.sh \
    --mount=type=bind,from=ctx-packages,source=/packages.lock,target=/ctx/packages.lock \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/install-packages.sh

# Forked cosmic-comp from the comp-build stage (ledger 0015)
RUN --mount=type=bind,from=ctx-comp,source=/install-comp.sh,target=/ctx/install-comp.sh \
    --mount=type=bind,from=comp-build,source=/out,target=/comp \
    /ctx/install-comp.sh

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
RUN /usr/bin/topaz check && \
    bootc container lint --fatal-warnings && \
    bash -c 'shopt -s nullglob; \
             sidecars=(/usr/share/rpm/*.sqlite-{wal,shm} \
                       /usr/lib/sysimage/libdnf5/*.sqlite-{wal,shm}); \
             [ ${#sidecars[@]} -eq 0 ]'
