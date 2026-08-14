#!/bin/bash

# Shared machinery for the package layers (ledgers 0020, 0022). Each
# package layer is one RUN installing one exact-NEVRA lockfile, and every
# RUN commits whatever it leaves behind — so each layer must end in a
# committable state itself: reproducible rpm metadata, canonical scriptlet
# output, and no /var or /run debris. The steps live here once; the
# per-layer scripts define only what their layer installs.

# rpm exits 0 even when its database is corrupt — it skips unreadable
# headers with only a note on stderr. A layer that trusts such a read
# fails much later with misleading symptoms (2026-08-12: a torn rpmdb
# made dnf5 lose the release version and die on a literal-$releasever
# mirror 404, two steps after rpm had already said "region trailer:
# BAD"). Every database read below routes stderr here; any output
# fails the layer on the spot.
rpm_stderr_fatal() {
    [ -s /tmp/rpm-stderr ] || return 0
    cat /tmp/rpm-stderr >&2
    echo "rpm reported database errors — the rpm database this layer" >&2
    echo "inherited is unreadable. In CI, suspect a poisoned entry in the" >&2
    echo "registry build cache (podman never overwrites an existing cache" >&2
    echo "key, so a bad entry persists until deleted from the" >&2
    echo "topaz-os-build-cache package)." >&2
    exit 1
}

# One line per installed package, stable order, for lockfile deltas.
census() {
    local pkgs
    pkgs=$(rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH} %{SOURCERPM}\n' \
        2> /tmp/rpm-stderr)
    rpm_stderr_fatal
    grep -v '^gpg-pubkey' <<< "$pkgs" | LC_ALL=C sort
}

### Reproducible package installs, prologue (ledger 0020)
# rpm stamps wall-clock INSTALLTIME/INSTALLTID into the rpm database, so
# two builds of an identical package set differ byte-wise. rpm honors
# SOURCE_DATE_EPOCH at install time; clamp it to the newest install time
# already in the database (the base image's for the first package layer, the
# previous layer's for the ones after), so the database only changes when
# the package set does.
clamp_install_times() {
    local times
    times=$(rpm -qa --qf '%{INSTALLTIME}\n' 2> /tmp/rpm-stderr)
    rpm_stderr_fatal
    SOURCE_DATE_EPOCH=$(sort -n <<< "$times" | tail -1)
    export SOURCE_DATE_EPOCH
}

# Install the exact NEVRA closure recorded in a lockfile ($1); any further
# arguments are passed to dnf5 (the main layer excludes a weak dependency
# this way). Names are resolved only when the lock is regenerated
# (build_files/gen-lockfile.sh). Weak dependencies stay off: the locks are
# resolved without them (wanted ones are named in gen-lockfile.sh), so a
# Recommends of a locked package must not ride along here either — the
# census assert would fail the build on the surplus. Fedora's repositories
# drop superseded builds, so any locked package the mirrors no longer serve
# is fetched from koji, which keeps every build permanently at a path
# derived from its source rpm (the lockfile's second field).
locked_install() {
    local lock=$1
    shift
    awk '/^\+/ { print substr($1, 2), $2 }' "$lock" > /tmp/lock.adds

    # Availability check on epoch-less name-ver-rel.arch (epoch never
    # affects what a mirror serves); anything missing gets a koji URL.
    # shellcheck disable=SC2046 # NEVRAs contain no whitespace; splitting is wanted
    dnf5 -q repoquery --queryformat '%{name}-%{version}-%{release}.%{arch}\n' \
        $(cut -d' ' -f1 /tmp/lock.adds) | LC_ALL=C sort -u > /tmp/repo.nvras
    local specs=()
    local nevra srpm nvra src srcrel rest srcver srcname arch
    while read -r nevra srpm; do
        nvra=$(sed 's/-[0-9]*:/-/' <<< "$nevra")
        if grep -qxF "$nvra" /tmp/repo.nvras; then
            specs+=("$nevra")
        else
            src=${srpm%.src.rpm}
            srcrel=${src##*-}
            rest=${src%-*}
            srcver=${rest##*-}
            srcname=${rest%-*}
            arch=${nvra##*.}
            echo "locked ${nvra} is no longer on the mirrors; using koji" >&2
            specs+=("https://kojipkgs.fedoraproject.org/packages/${srcname}/${srcver}/${srcrel}/${arch}/${nvra}.rpm")
        fi
    done < /tmp/lock.adds
    dnf5 -y install --setopt=install_weak_deps=False "$@" "${specs[@]}"
}

### Locked package set, epilogue (ledger 0022)
# Assert that this layer's delta over the pre-install census ($2) is
# byte-for-byte the committed lockfile ($1) — weak deps, conflicts and
# scriptlet side effects included — and ship the delta in the image so
# `topaz check` can re-verify it on a booted system.
verify_layer_delta() {
    local lock=$1 pre=$2
    census > /tmp/rpm-post.list
    {
        LC_ALL=C comm -13 "$pre" /tmp/rpm-post.list | sed 's/^/+/'
        LC_ALL=C comm -23 "$pre" /tmp/rpm-post.list | sed 's/^/-/'
    } > /tmp/packages.delta
    if ! diff -u "$lock" /tmp/packages.delta; then
        echo "Installed package set does not match $(basename "$lock")." >&2
        echo "The locked install and the lock disagree — check gen-lockfile.sh" >&2
        echo "and the transaction output above; 'just lock' rebases the lock." >&2
        exit 1
    fi
    mkdir -p /usr/share/topaz-os
    cp /tmp/packages.delta /usr/share/topaz-os/"$(basename "$lock")"
    chmod 644 /usr/share/topaz-os/"$(basename "$lock")"
}

# Leave the layer committable: reproducible rpm databases, canonical
# scriptlet output, no /var or /run debris.
commit_clean_layer() {
    ### Reproducible package installs, epilogue (ledger 0020)
    # rpm leaves its sqlite databases in WAL journal mode. A WAL database
    # is unreadable without its -wal/-shm sidecars, and those are
    # nondeterministic runtime state the image must not ship — but dropping
    # them from a WAL-mode database breaks every rpm query on the booted
    # system, where read-only /usr prevents recreating them. Checkpoint and
    # convert to DELETE journal mode after the layer's last database write
    # (a later package layer's dnf run flips its database back to WAL, so
    # every package layer ends with this). python3's sqlite3 module, not
    # the sqlite CLI: the base image ships the former but not the latter.
    #
    # The conversion runs on a tmpfs copy, never in place: sqlite page
    # surgery on a database inherited through an overlayfs copy-up once
    # committed a torn file (2026-08-12, "h# 2322 region trailer: BAD" —
    # which a failed run's --cache-to then served to every later build).
    # The sidecars travel with the copy (the -wal holds the final
    # unCheckpointed writes), the converted database is integrity-checked
    # so a torn result fails this layer before it can be committed or
    # cached, and the copy back is a single sequential write.
    local db tmp side
    for db in /usr/share/rpm/rpmdb.sqlite \
              /usr/lib/sysimage/libdnf5/transaction_history.sqlite; do
        tmp="/tmp/$(basename "$db")"
        cp "$db" "$tmp"
        for side in wal shm; do
            if [ -e "$db-$side" ]; then
                cp "$db-$side" "$tmp-$side"
            fi
        done
        python3 -c '
import sqlite3, sys
con = sqlite3.connect(sys.argv[1], isolation_level=None)
con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
con.execute("PRAGMA journal_mode=DELETE")
verdict = con.execute("PRAGMA integrity_check").fetchone()[0]
con.close()
if verdict != "ok":
    sys.exit(f"{sys.argv[1]}: integrity_check: {verdict}")
' "$tmp"
        rm -f "$db" "$db-wal" "$db-shm"
        cp "$tmp" "$db"
        chmod 0644 "$db"
        rm -f "$tmp" "$tmp-wal" "$tmp-shm"
    done

    # libxml2's xmlcatalog assembles SGML catalogs in a hash table seeded
    # per process, so the docbook-dtds %post (historically reached through
    # kde-connect's kf6-kdoctools dependency; kept in case a future
    # dependency reinstalls it) writes the /etc/sgml catalogs in a fresh
    # line order on every install. The lines only delegate to disjoint
    # per-DTD catalogs, so order carries no meaning — sort each file into a
    # canonical order. Conditional because only the layer that pulls
    # docbook-dtds creates these files; when they exist, the grep still
    # fails the build loudly if the format drifts.
    if [ -e /etc/sgml/catalog ]; then
        grep -q '^CATALOG ' /etc/sgml/catalog
        local f
        for f in /etc/sgml/catalog /etc/sgml/*.cat; do
            [ -L "$f" ] && continue
            LC_ALL=C sort -o "$f" "$f"
        done
    fi

    # The build has committed silently torn files rewritten through an
    # overlayfs copy-up (2026-08-13: authselect.conf and both XML catalogs
    # with NUL-padded tails — new file size, old or missing data blocks —
    # and a SELinux module store abandoned mid-transaction after rename()
    # of a lower-layer directory returned EXDEV and libsemanage's
    # non-atomic fallback collided with the debris; greetd's module was
    # silently missing from the published image). The scriptlets swallow
    # these failures and the build stays green, so verify the state they
    # should have left and fail the layer before a torn result can be
    # committed or cached. Same principle as the rpm database integrity
    # check above: the tools' exit codes cannot be trusted through an
    # overlay, the resulting files can.
    # (xmllint suffices as the tear detector: the observed tears pad with
    # NUL bytes, which are never well-formed XML. No tail-shape check — a
    # legitimately empty catalog self-closes its root element.)
    local cat
    for cat in /etc/xml/catalog /etc/sgml/docbook/xmlcatalog; do
        [ -e "$cat" ] || continue
        xmllint --noout "$cat"
    done
    [ ! -e /etc/selinux/targeted/previous ]
    [ ! -e /etc/selinux/targeted/tmp ]
    [ ! -e /etc/selinux/final/targeted ]
    if rpm -q greetd-selinux > /dev/null 2>&1; then
        [ -d /etc/selinux/targeted/active/modules/200/greetd ]
    fi

    ### Empty /var (ledger 0024)
    # /var is machine state: the image ships none (only an empty /var/tmp,
    # matching the base), and everything a dnf run leaves there is a
    # reproducibility hazard (countme cookies roll a random request budget
    # per build). Scrub at the end of the same RUN so none of it is ever
    # committed. podman mounts files at arbitrary depth under /run
    # (resolv.conf, secrets): skip mounted trees and tolerate busy leaves —
    # mount contents never commit, and the check/lint gate in the
    # Containerfile is the authority on what actually ships.
    local p
    for p in /var/* /var/.[!.]* /run/* /run/.[!.]*; do
        [ -e "$p" ] || continue
        findmnt -n "$p" > /dev/null && continue
        rm -rf "$p" 2>/dev/null || true
    done
    mkdir -p /var/tmp
}
