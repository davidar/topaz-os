#!/bin/bash

# Rewrite a built image into content-based layers with chunkah
# (ledger 0028). Runs outside the Containerfile, against the image the
# build produced: the Containerfile's coarse content-keyed layers remain
# the build-cache units, and this reshapes only the published artifact,
# so machines download the packages that changed instead of a whole
# locked-install layer.

set -ouex pipefail

image=$1  # name:tag in the invoking user's containers-storage
outdir=$2 # OCI directory to create (must not already exist)

# podman build stores unqualified tags under localhost/; podman resolves
# the short name back, but skopeo's containers-storage: reference does
# not — it assumes docker.io. Qualify unless a registry is already given.
case "$image" in
*/*) ;;
*) image="localhost/${image}" ;;
esac

# Pinned tool; Renovate tracks the digest (.github/renovate.json5).
chunkah_image="quay.io/coreos/chunkah:latest@sha256:f812b02f304ac192cdfa722a7043fd775fa03ed48fa047ff8213c1fe1c4637ab"

# Scratch space next to the output, not /tmp: the compressed layers are
# ~5 GiB, which a tmpfs /tmp would swallow into RAM.
workdir=$(mktemp -d "$(dirname "$outdir")/.chunk.XXXXXX")
trap 'rm -rf "$workdir"' EXIT

# The image config travels as a file: it is ~130 KiB of JSON, past the
# kernel's per-string exec limit for an environment variable.
skopeo inspect --config "containers-storage:${image}" > "${workdir}/config.json"

# SOURCE_DATE_EPOCH=0 matches the build's --timestamp 0 (Justfile): the
# same input image must chunk to byte-identical output, or the weekly
# reproducibility check could never hold. --prune /sysroot/ and the
# ostree label removals are chunkah's documented bootc recipe — the
# labels describe the pre-chunk layer set and would be stale here.
# --max-layers 400: measured on a real update, 128 layers packed ~11
# packages each and re-shipped ~477 MiB of unchanged bystanders when one
# package moved; at 400 that collateral fell to ~19 MiB. Stay under
# containers-storage's limit of 500 layers.
podman run --rm \
    --mount="type=image,src=${image},dest=/chunkah" \
    -v "${workdir}/config.json:/config.json:ro,z" \
    -v "${workdir}:/work:z" \
    -e SOURCE_DATE_EPOCH=0 \
    "$chunkah_image" build \
    --config /config.json \
    --prune /sysroot/ \
    --max-layers 400 \
    --compressed \
    --label ostree.commit- --label ostree.final-diffid- \
    --output oci:/work/out

mv "${workdir}/out" "$outdir"
