#!/bin/bash
# Seed a containers blob-info-cache so `skopeo copy --dest-compress-format
# zstd:chunked` reuses the published image's blobs instead of recompressing
# every layer on every push (ledger 0031).
#
#   seed-blob-cache.sh <chunked-oci-dir> <published-ref> <cache-dir>
#
# skopeo's cache learns the gzip↔uncompressed↔zstd digest relations only
# by doing the compression itself, which a stateless CI runner never
# remembers — so a no-change push would recompress all ~400 layers
# (~20 min of runner CPU) just to discover the registry already has the
# result. Every fact the cache needs is already public, though: the
# local chunked manifest pairs each gzip digest with its diff_id, and a
# published manifest pairs the same diff_ids with the zstd digests and
# their zstd:chunked TOC annotations. This script joins the two on
# diff_id and writes the rows skopeo's substitution logic reads
# (verified against skopeo 1.22.2: candidates need the location row, and
# a reusing push is byte-identical to a recompressing one). skopeo then
# HEAD-verifies each candidate against the registry before trusting it,
# so a stale or wrong row degrades to recompression, never corruption.
#
# The requested ref (normally :latest) can lag reality: a run that dies
# between pushing its identity tag and re-aliasing :latest leaves every
# freshly-converted blob in the registry under a tag :latest knows
# nothing about. Blobs belong to the repository, not the tag, so recent
# identity tags are consulted alongside the requested ref and all their
# rows unioned — whichever published image holds a layer seeds it.
#
# Layers whose diff_id is absent from every consulted image (the actual
# update delta) get no rows and are compressed for real.
set -euo pipefail

oci_dir=$1
ref=$2
cache_dir=$3

registry=${ref%%/*}
repo=${ref%:*}
db="$cache_dir/blob-info-cache-v1.sqlite"
mkdir -p "$cache_dir"

manifest_digest=$(jq -r '.manifests[0].digest' "$oci_dir/index.json" | cut -d: -f2)
local_manifest="$oci_dir/blobs/sha256/$manifest_digest"
config_digest=$(jq -r '.config.digest' "$local_manifest" | cut -d: -f2)
local_config="$oci_dir/blobs/sha256/$config_digest"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Identity tags are latest-<date>-<sha>, so a lexical sort orders them
# by date; same-date attempts sort arbitrarily, which is why several are
# consulted rather than one "newest".
candidates=("$ref")
recent=$(skopeo list-tags "docker://$repo" 2>/dev/null | jq -r '.Tags[]' \
    | grep -E '^latest-[0-9]{8}-' | sort | tail -n 5) || true
for tag in $recent; do
    [ "$repo:$tag" = "$ref" ] || candidates+=("$repo:$tag")
done

# Pair layers with diff_ids by position in each image, join on diff_id.
# Output: diff_id, local digest, zstd digest, TOC annotations (compact
# JSON). Published layers without the full zstd:chunked annotation set
# are dropped — gzip layers in an old or mixed-compression image carry
# none, and reusing a zstd layer without its TOC would publish a layer
# clients cannot partially pull. Published manifests run to hundreds of
# kilobytes (~400 layers with TOC annotations) — far past the kernel's
# single-argument limit, so they travel by file (--slurpfile), never by
# --argjson.
rows_file="$workdir/rows.tsv"
: > "$rows_file"
for cand in "${candidates[@]}"; do
    if ! skopeo inspect --no-tags --raw "docker://$cand" \
            > "$workdir/pub-manifest.json" 2>/dev/null \
        || ! skopeo inspect --no-tags --raw --config "docker://$cand" \
            > "$workdir/pub-config.json" 2>/dev/null; then
        echo "no published image at $cand — skipping"
        continue
    fi
    jq -rn \
        --slurpfile lm "$local_manifest" --slurpfile lc "$local_config" \
        --slurpfile pm "$workdir/pub-manifest.json" \
        --slurpfile pc "$workdir/pub-config.json" '
        def pairs($m; $c): [$m.layers, $c.rootfs.diff_ids] | transpose
            | map({diff: .[1], layer: .[0]});
        (pairs($pm[0]; $pc[0])
            | map(select(.layer.annotations
                  | has("io.github.containers.zstd-chunked.manifest-checksum")))
            | INDEX(.diff)) as $pub
        | pairs($lm[0]; $lc[0])[]
        | $pub[.diff] as $p | select($p)
        | [.diff, .layer.digest, $p.layer.digest, ($p.layer.annotations | tojson)]
        | @tsv' > "$workdir/ref-rows.tsv"
    echo "$cand: $(wc -l < "$workdir/ref-rows.tsv") reusable layers"
    cat "$workdir/ref-rows.tsv" >> "$rows_file"
done

rows=$(sort -u "$rows_file")
if [ -z "$rows" ]; then
    echo "no reusable layers found in $repo — nothing to seed"
    exit 0
fi

# The schema must match what skopeo 1.22.2 creates (it opens with
# CREATE TABLE IF NOT EXISTS, so agreeing on the shape is enough).
{
    cat <<'SQL'
CREATE TABLE IF NOT EXISTS DigestUncompressedPairs(
    anyDigest TEXT PRIMARY KEY NOT NULL, uncompressedDigest TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS DigestUncompressedPairs_index_uncompressedDigest
    ON DigestUncompressedPairs(uncompressedDigest);
CREATE TABLE IF NOT EXISTS DigestCompressors(
    digest TEXT PRIMARY KEY NOT NULL, compressor TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS DigestSpecificVariantCompressors(
    digest TEXT PRIMARY KEY NOT NULL, specificVariantCompressor TEXT NOT NULL,
    specificVariantAnnotations BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS KnownLocations(
    transport TEXT NOT NULL, scope TEXT NOT NULL, digest TEXT NOT NULL,
    location TEXT NOT NULL, time TIMESTAMP NOT NULL,
    PRIMARY KEY (transport, scope, digest, location));
BEGIN;
SQL
    while IFS=$'\t' read -r diff gz zst ann; do
        printf "INSERT OR IGNORE INTO DigestUncompressedPairs VALUES('%s','%s'),('%s','%s');\n" \
            "$gz" "$diff" "$zst" "$diff"
        printf "INSERT OR IGNORE INTO DigestCompressors VALUES('%s','gzip'),('%s','zstd');\n" \
            "$gz" "$zst"
        printf "INSERT OR IGNORE INTO DigestSpecificVariantCompressors VALUES('%s','zstd:chunked','%s');\n" \
            "$zst" "$ann"
        printf "INSERT OR IGNORE INTO KnownLocations VALUES('docker','%s','%s','%s',strftime('%%Y-%%m-%%d %%H:%%M:%%S','now'));\n" \
            "$registry" "$zst" "$repo"
    done <<<"$rows"
    echo "COMMIT;"
} | sqlite3 "$db"

echo "seeded $(cut -f1 <<<"$rows" | sort -u | wc -l) reusable layers from $repo into $db"
