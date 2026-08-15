#!/bin/bash
# alias-tags.sh <registry-host> <repo> <digest> <tag>...
#
# Point additional tags at an already-pushed manifest by PUTting its
# exact bytes — fetched back by digest, so they are exactly what was
# published — under each name. A registry tag is only a name for a
# manifest, so this replaces N full copies with N tiny PUTs.
#
# Credentials arrive via ALIAS_CREDS (user:token), keeping them out of
# argv; callers run this outside xtrace so the bearer token never
# reaches a public log.
set -euo pipefail

host=$1 repo=$2 digest=$3
shift 3

case "$host" in
    ghcr.io) token_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull,push" ;;
    quay.io) token_url="https://quay.io/v2/auth?service=quay.io&scope=repository:${repo}:pull,push" ;;
    *) echo "no token recipe for registry $host" >&2; exit 1 ;;
esac

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
umask 077
token=$(curl -fsS -u "$ALIAS_CREDS" "$token_url" | jq -r .token)
printf 'header = "Authorization: Bearer %s"\n' "$token" > "$workdir/curl-auth"
curl -fsS --config "$workdir/curl-auth" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    -o "$workdir/manifest.json" \
    "https://${host}/v2/${repo}/manifests/${digest}"
# chunkah-derived manifests omit the optional top-level mediaType;
# registries reject a PUT whose Content-Type is the literal "null"
media_type=$(jq -r '.mediaType // "application/vnd.oci.image.manifest.v1+json"' \
    "$workdir/manifest.json")
for tag in "$@"; do
    echo "aliasing :${tag} -> ${digest}"
    curl -fsS -X PUT --config "$workdir/curl-auth" \
        -H "Content-Type: ${media_type}" \
        --data-binary "@$workdir/manifest.json" \
        "https://${host}/v2/${repo}/manifests/${tag}"
done
