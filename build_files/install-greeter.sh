#!/bin/bash

# Greeter layer: the forked cosmic-greeter binary, keyed on the
# greeter-build stage's output (pinned by COSMIC_GREETER_REF in the
# Containerfile).

set -ouex pipefail

### Forked cosmic-greeter (JXL wallpapers, fingerprint re-arm)
# The Fedora binary is replaced with a build of the topaz fork
# (github.com/davidar/cosmic-greeter, compiled in the Containerfile's
# greeter-build stage at a pinned commit): JPEG XL wallpaper decoding on
# the greeter and lock screen, fingerprint re-arming on wake, and lock
# state reported to logind, pending upstream. Ledger 0034. Guard: fail
# loudly when Fedora bumps cosmic-greeter, so the fork gets rebased
# rather than silently shadowing a newer base version. Only the UI
# binary is replaced; cosmic-greeter-daemon stays Fedora's.
fork_base_version=1.6.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-greeter)
if [ "$packaged_version" != "$fork_base_version" ]; then
    echo "cosmic-greeter is now $packaged_version but the fork is based on $fork_base_version" >&2
    echo "Rebase github.com/davidar/cosmic-greeter (branch auth-rearm) and update COSMIC_GREETER_REF" >&2
    exit 1
fi
install -m0755 /greeter/cosmic-greeter /usr/bin/cosmic-greeter
{ cat /greeter/fork-info; echo "base=$fork_base_version"; } \
    > /usr/share/topaz-os/cosmic-greeter-fork
