# Build context: scripts and system files referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Base: Bluefin DX with NVIDIA open kernel modules
FROM ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable@sha256:c46734507cf7e10ab6008b5a6658244fc8d6e2b2a0ba5fade8496195fdf23738

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Verify final image and contents are correct
RUN bootc container lint
