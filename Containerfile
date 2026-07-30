# Build context: scripts and system files referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
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
ARG COSMIC_COMP_REF=5568abdcc88fd27297514be6446cc5c35b509f03
RUN dnf -y install gcc cargo rust pkgconf-pkg-config git-core \
    libseat-devel libinput-devel systemd-devel mesa-libgbm-devel \
    libxkbcommon-devel pixman-devel wayland-devel libglvnd-devel \
    libdisplay-info-devel fontconfig-devel clang-libs && dnf clean all
RUN git init -q /src && \
    git -C /src fetch --depth=1 "$COSMIC_COMP_REPO" "$COSMIC_COMP_REF" && \
    git -C /src checkout -q FETCH_HEAD && \
    cargo build --release --manifest-path=/src/Cargo.toml && \
    install -Dm0755 /src/target/release/cosmic-comp /out/cosmic-comp && \
    printf 'repo=%s\nref=%s\n' "$COSMIC_COMP_REPO" "$COSMIC_COMP_REF" \
        > /out/fork-info

# Base: Bluefin DX with NVIDIA open kernel modules
FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable@sha256:c46734507cf7e10ab6008b5a6658244fc8d6e2b2a0ba5fade8496195fdf23738

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=comp-build,source=/out,target=/comp \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Verify final image and contents are correct, and that the image still
# matches the claims in its provenance ledger
RUN /usr/bin/topaz check
RUN bootc container lint

# Last step by necessity: the check gate's own rpm queries recreate these
# sqlite sidecars, whose bytes are nondeterministic and would churn the
# rpmdb chunk on every rebuild (ledger 0020). CI asserts the published
# artifact ships without them.
RUN rm -f /usr/share/rpm/rpmdb.sqlite-wal /usr/share/rpm/rpmdb.sqlite-shm \
    /usr/lib/sysimage/libdnf5/*.sqlite-wal /usr/lib/sysimage/libdnf5/*.sqlite-shm
