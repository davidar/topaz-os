# topaz-os recipes (imported via the 60-custom.just hook in 00-entry.just)

# Fetch topaz-home, the userland companion repo (clones only, never applies)
topaz-home dest="$HOME/topaz-home":
    #!/usr/bin/bash
    set -euo pipefail
    dest="{{ dest }}"
    if [ -e "$dest" ]; then
        echo "$dest already exists — pull updates there instead."
    else
        git clone https://github.com/davidar/topaz-home "$dest"
    fi
    echo "Next steps (nothing has been applied):"
    echo "  cd $dest"
    echo "  just apply     # install the layer plumbing"
    echo "  just --list    # see the opt-in component verbs"
