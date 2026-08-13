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
shift 2
# Remaining arguments: --label and --annotation key=value pairs to stamp
# on the output. The build applies no labels of its own (they would
# poison its layer cache keys — see the Justfile), so the caller provides
# them here and they take precedence over same-key labels inherited from
# the base.
caller_args=("$@")

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

# chunkah does not carry the config file's labels into the output image
# (21 labels in, 0 out, observed at the pinned digest) — silently losing
# everything the base image declares. (Manifest annotations are dropped
# the same way, which is why the caller must pass the created annotation
# explicitly: bootc reads the deployment's ostree commit timestamp from
# it.) Re-add every inherited label explicitly, minus the two ostree
# ones chunkah's bootc recipe strips anyway (they describe the pre-chunk
# layer set and would be stale) and minus any key the caller is stamping
# itself, so the caller's value wins regardless of how chunkah orders
# duplicate --label flags.
caller_keys=()
for ((i = 0; i + 1 < ${#caller_args[@]}; i += 2)); do
    if [ "${caller_args[i]}" = "--label" ]; then
        caller_keys+=("${caller_args[i + 1]%%=*}")
    fi
done
caller_keys_json=$(printf '%s\n' "${caller_keys[@]+"${caller_keys[@]}"}" \
    | jq -R . | jq -s .)
label_args=()
while IFS= read -r kv; do
    label_args+=(--label "$kv")
done < <(jq -r --argjson drop "$caller_keys_json" '.config.Labels // {}
    | del(."ostree.commit", ."ostree.final-diffid")
    | with_entries(select(.key as $k | $drop | index($k) | not))
    | to_entries[] | "\(.key)=\(.value)"' "${workdir}/config.json")

# SOURCE_DATE_EPOCH=0 matches the build's --timestamp 0 (Justfile): the
# same input image must chunk to byte-identical output, or the weekly
# reproducibility check could never hold. --prune /sysroot/ is chunkah's
# documented bootc recipe.
# --max-layers 400: measured on a real update, 128 layers packed ~11
# packages each and re-shipped ~477 MiB of unchanged bystanders when one
# package moved; at 400 that collateral fell to ~19 MiB. Stay under
# containers-storage's limit of 500 layers.
podman run --rm \
    --mount="type=image,src=${image},destination=/chunkah" \
    -v "${workdir}/config.json:/config.json:ro,z" \
    -v "${workdir}:/work:z" \
    -e SOURCE_DATE_EPOCH=0 \
    "$chunkah_image" build \
    --config /config.json \
    --prune /sysroot/ \
    --max-layers 400 \
    --compressed \
    "${label_args[@]}" \
    "${caller_args[@]+"${caller_args[@]}"}" \
    --output oci:/work/out

mv "${workdir}/out" "$outdir"
