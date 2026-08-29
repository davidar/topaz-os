#!/usr/bin/env bash
# VM verification harness — boots the locally built image in QEMU and
# machine-checks the post-boot state over ssh instead of relying on a
# human at the console. See tests/README.md.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
source "$TESTS_DIR/lib.sh"

usage() {
    sed -n 's/^#usage#\( \|$\)//p' "${BASH_SOURCE[0]}"
}

#usage# Usage: tests/run.sh <command>
#usage#   all [suite]   build what's missing, boot, run the suite, shut down
#usage#                 (default suite: boot-verify; disk build needs sudo)
#usage#   image         build the derived test image (rootless podman)
#usage#   disk          build the test qcow2 via bootc-image-builder (sudo)
#usage#   start | stop | status
#usage#   ssh [cmd...]  shell into the running VM as the test user
#usage#   suite <name>  run tests/suites/<name>.sh against the running VM
#usage#                 (a path runs that suite file — companion repos)
#usage#   screendump [out.png]

cmd="${1:-all}"
shift || true
case "$cmd" in
image) build_image ;;
disk) build_disk ;;
start) vm_start ;;
stop) vm_stop ;;
status) vm_status ;;
ssh) tssh "$@" ;;
suite) run_suite "${1:?suite name}" ;;
screendump) screendump "${1:-}" ;;
all)
    build_image
    if disk_stale; then
        echo "test disk missing or built from an older image — rebuilding (sudo)"
        build_disk
    fi
    vm_start
    trap vm_stop EXIT
    run_suite "${1:-boot-verify}"
    ;;
*)
    usage
    exit 2
    ;;
esac
