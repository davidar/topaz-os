#!/bin/bash

# Compositor layer: the forked cosmic-comp binary, keyed on the comp-build
# stage's output (pinned by COSMIC_COMP_REF in the Containerfile).

set -ouex pipefail

### Forked cosmic-comp (config-driven workspace gestures)
# The Fedora binary is replaced with a build of the topaz fork
# (github.com/davidar/cosmic-comp, compiled in the Containerfile's
# comp-build stage at a pinned commit): workspace-swipe finger count, swipe
# physics, and rubber-band edge bounce become hot-reloadable config, pending
# upstream (pop-os/cosmic-epoch#54). Ledger 0015. Guard: fail loudly when
# Fedora bumps cosmic-comp, so the fork gets rebased rather than silently
# shadowing a newer base version.
fork_base_version=1.5.0
packaged_version=$(rpm -q --qf '%{VERSION}' cosmic-comp)
if [ "$packaged_version" != "$fork_base_version" ]; then
    echo "cosmic-comp is now $packaged_version but the fork is based on $fork_base_version" >&2
    echo "Rebase github.com/davidar/cosmic-comp (branch topaz) and update COSMIC_COMP_REF" >&2
    exit 1
fi
install -m0755 /comp/cosmic-comp /usr/bin/cosmic-comp
{ cat /comp/fork-info; echo "base=$fork_base_version"; } \
    > /usr/share/topaz-os/cosmic-comp-fork
