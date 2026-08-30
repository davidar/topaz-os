# shellcheck shell=bash
# Shared helpers for the VM verification harness, sourced by run.sh and
# by the suites. Suites use the check/verdict helpers at the bottom.

TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ART="$TESTS_DIR/.artifacts"
mkdir -p "$ART"

BASE_IMAGE="${TOPAZ_TEST_BASE_IMAGE:-localhost/topaz-os:test}"
TEST_IMAGE="localhost/topaz-os-test:latest"
BIB_IMAGE="${TOPAZ_TEST_BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"
DISK="$ART/disk.qcow2"
SSH_PORT="${TOPAZ_TEST_SSH_PORT:-2233}"
SSH_KEY="$ART/id_ed25519"
QMP_SOCK="$ART/qmp.sock"
PIDFILE="$ART/qemu.pid"
# UEFI firmware lives under different names per distro (Fedora, Ubuntu).
OVMF_CODE=""
for _fw in /usr/share/edk2/ovmf/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd; do
    [[ -f "$_fw" ]] && { OVMF_CODE="$_fw"; break; }
done
OVMF_VARS="${OVMF_CODE/CODE/VARS}"

# --- image and disk builds --------------------------------------------------

build_image() {
    podman build --build-arg "BASE=$BASE_IMAGE" -t "$TEST_IMAGE" \
        -f "$TESTS_DIR/Containerfile.test" "$TESTS_DIR"
}

ensure_key() {
    [[ -f "$SSH_KEY" ]] || ssh-keygen -q -t ed25519 -N '' -C topaz-test -f "$SSH_KEY"
}

disk_stale() {
    [[ ! -f "$DISK" ]] && return 0
    local built current
    built="$(cat "$ART/disk.image-id" 2>/dev/null || true)"
    current="$(podman image inspect -f '{{.Id}}' "$TEST_IMAGE" 2>/dev/null || true)"
    [[ -z "$built" || "$built" != "$current" ]]
}

# Rootful step: bootc-image-builder reads the image from root container
# storage and runs privileged. Everything else in the harness is rootless.
# The rootful commands run in a single escalated shell so the escalation
# prompt fires exactly once, up front — set TOPAZ_TEST_SUDO=pkexec to
# authorize via the polkit dialog instead of sudo.
build_disk() {
    ensure_key
    sed "s|@SSH_PUBKEY@|$(cat "$SSH_KEY.pub")|" \
        "$TESTS_DIR/disk-test.toml.in" >"$ART/disk-test.toml"

    # TMPDIR for the image copy matters: the transfer stages ~13 GB and
    # /tmp is tmpfs. All paths and ids are expanded here and passed as
    # arguments — the escalated shell starts from a clean environment.
    local tmp="$ART/scp-tmp" out="$ART/bib-out"
    mkdir -p "$tmp" "$out"
    # shellcheck disable=SC2016  # the escalated shell expands its own args
    "${TOPAZ_TEST_SUDO:-sudo}" bash -euo pipefail -c '
        tmp="$1" test_image="$2" bib_image="$3" toml="$4" out="$5" uid="$6" owner="$7"
        # pkexec starts us in root'\''s 0700 home; podman image scp re-execs
        # its rootless side as the user, which must be able to chdir back
        # to the inherited cwd. Every path below is absolute anyway.
        cd /
        # An already-root caller (CI runs the whole harness rootful) built
        # the image straight into root storage — no cross-user copy.
        if [ "$uid" != 0 ]; then
            env TMPDIR="$tmp" podman image scp \
                "$uid@localhost::$test_image" "root@localhost::$test_image"
        fi
        podman run --rm --privileged --pull=newer --net=host \
            --security-opt label=type:unconfined_t \
            -v "$toml:/config.toml:ro" \
            -v "$out:/output" \
            -v /var/lib/containers/storage:/var/lib/containers/storage \
            "$bib_image" --type qcow2 --use-librepo=True --rootfs=btrfs \
            "$test_image"
        chown -R "$owner" "$out"
    ' build-disk-rootful "$tmp" "$TEST_IMAGE" "$BIB_IMAGE" \
        "$ART/disk-test.toml" "$out" "$(id -u)" "$(id -u):$(id -g)"
    rm -rf "$tmp"
    mv -f "$out/qcow2/disk.qcow2" "$DISK"
    rm -rf "$out"
    podman image inspect -f '{{.Id}}' "$TEST_IMAGE" >"$ART/disk.image-id"
}

# --- VM lifecycle -----------------------------------------------------------

vm_running() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

vm_start() {
    if vm_running; then
        echo "VM already running (pid $(cat "$PIDFILE"))"
        return 0
    fi
    [[ -f "$DISK" ]] || { echo "no test disk — run: tests/run.sh disk" >&2; return 1; }
    [[ -f "$OVMF_CODE" ]] || { echo "no OVMF firmware — install edk2-ovmf (Fedora) or ovmf (Ubuntu)" >&2; return 1; }
    [[ -f "$ART/OVMF_VARS.fd" ]] || cp "$OVMF_VARS" "$ART/OVMF_VARS.fd"

    # -snapshot: every run boots a pristine disk; set TOPAZ_TEST_PERSIST=1
    # to keep changes across boots (e.g. while iterating inside the VM).
    local snapshot=(-snapshot)
    [[ "${TOPAZ_TEST_PERSIST:-0}" = 1 ]] && snapshot=()

    # virgl gives the guest a real EGL path. Plain virtio-vga leaves clients
    # with no usable renderer: niri limps along but scans out black, and
    # portal-cosmic hangs before claiming its bus name, wedging the portal
    # frontend. The host side of the GL context adapts to the hardware:
    #   egl  — render on the host GPU (egl-headless), plus a VNC listener
    #          (unix socket, nothing exposed) that screendump() reads and
    #          that doubles as a debug viewer.
    #   sdl  — GPU-less hosts, e.g. CI runners: SDL's offscreen driver
    #          hosts the context on llvmpipe. QEMU refuses a VNC listener
    #          beside an SDL GL context, so screendump() captures inside
    #          the guest instead.
    #   none — no GL at all; boots, but expect the wedges above.
    # TOPAZ_TEST_DISPLAY overrides the detection.
    local display="${TOPAZ_TEST_DISPLAY:-auto}"
    if [[ "$display" = auto ]]; then
        if compgen -G '/dev/dri/renderD*' >/dev/null; then
            display=egl
        else
            display=sdl
        fi
    fi
    rm -f "$ART/vnc.sock"
    local gpu=(-device virtio-vga-gl)
    case "$display" in
    egl) gpu+=(-display egl-headless -vnc "unix:$ART/vnc.sock") ;;
    sdl)
        export SDL_VIDEODRIVER=offscreen
        # shellcheck disable=SC2054  # the comma is QEMU option syntax
        gpu+=(-display sdl,gl=on)
        ;;
    none) gpu=(-device virtio-vga -display none -vnc "unix:$ART/vnc.sock") ;;
    *)
        echo "TOPAZ_TEST_DISPLAY must be auto, egl, sdl or none" >&2
        return 2
        ;;
    esac

    qemu-system-x86_64 \
        -name topaz-test -machine q35,accel=kvm -cpu host \
        -smp "${TOPAZ_TEST_CPUS:-4}" -m "${TOPAZ_TEST_RAM:-8G}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$ART/OVMF_VARS.fd" \
        -drive "file=$DISK,if=virtio,format=qcow2,discard=unmap" \
        "${snapshot[@]}" \
        "${gpu[@]}" \
        -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -device virtio-net-pci,netdev=n0 \
        -qmp "unix:$QMP_SOCK,server,nowait" \
        -serial "file:$ART/serial.log" \
        -pidfile "$PIDFILE" -daemonize
    echo "VM started (ssh -p $SSH_PORT, qmp $QMP_SOCK)"
}

vm_stop() {
    vm_running || { rm -f "$PIDFILE"; return 0; }
    local pid
    pid="$(cat "$PIDFILE")"
    qmp quit >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
    local _i
    for _i in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "VM stopped"
}

vm_status() {
    if vm_running; then
        echo "running (pid $(cat "$PIDFILE"), ssh -p $SSH_PORT)"
    else
        echo "not running"
    fi
}

# --- guest access -----------------------------------------------------------

tssh() {
    ssh -q -p "$SSH_PORT" -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 -o LogLevel=ERROR \
        tester@127.0.0.1 "$@"
}

qmp() {
    python3 "$TESTS_DIR/qmp.py" "$QMP_SOCK" "$@"
}

png_valid() { # non-empty, PNG signature, complete (IEND trailer present)
    [[ -s "$1" ]] &&
        [[ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" == 89504e470d0a1a0a ]] &&
        tail -c 12 "$1" | grep -q IEND
}

screendump() {
    local out="${1:-$ART/screens/screen-$(date +%Y%m%d-%H%M%S).png}"
    mkdir -p "$(dirname "$out")"
    out="$(realpath -m "$out")"
    if [[ -S "$ART/vnc.sock" ]]; then
        python3 "$TESTS_DIR/screendump.py" "$ART/vnc.sock" "$out" ||
            { echo "screendump failed" >&2; return 1; }
    else
        # No VNC listener (sdl display mode): capture inside the guest.
        # Weaker — needs the session up — but display-server-free hosts
        # have no hypervisor-side view of the GL scanout at all.
        # The compositor writes the file asynchronously after the action
        # returns, so wait until a complete PNG lands (an early read once
        # shipped a zero-byte artifact); the dir is cleared first so the
        # newest file is unambiguously this capture.
        # shellcheck disable=SC2016  # $(...) expands in the guest shell
        tssh 'export NIRI_SOCKET=$(systemctl --user show-environment | sed -n "s/^NIRI_SOCKET=//p")
            dir="$HOME/Pictures/Screenshots"
            mkdir -p "$dir" && rm -f "$dir"/*
            niri msg action screenshot-screen >/dev/null || exit 1
            shot=
            for _ in $(seq 40); do
                shot=$(ls -t "$dir" 2>/dev/null | head -1)
                [ -n "$shot" ] && tail -c 12 "$dir/$shot" 2>/dev/null | grep -q IEND && break
                shot=
                sleep 0.5
            done
            [ -n "$shot" ] || exit 1
            cat "$dir/$shot" && rm -f "$dir/$shot"' \
            >"$out" || { echo "screendump failed" >&2; return 1; }
    fi
    # Verify the state, not the tool's exit code: anything that is not a
    # complete PNG is a failed capture, kept aside as evidence instead of
    # masquerading as a screenshot in the artifact.
    if ! png_valid "$out"; then
        mv -f "$out" "$out.invalid" 2>/dev/null || rm -f "$out"
        echo "screendump produced an invalid PNG: $out" >&2
        return 1
    fi
    echo "$out"
}

wait_ssh() {
    local deadline=$((SECONDS + ${1:-300}))
    until tssh true 2>/dev/null; do
        ((SECONDS < deadline)) || { echo "timed out waiting for ssh" >&2; return 1; }
        sleep 3
    done
}

wait_user_graphical() {
    local deadline=$((SECONDS + ${1:-120}))
    until [[ "$(tssh systemctl --user is-active graphical-session.target 2>/dev/null)" == active ]]; do
        ((SECONDS < deadline)) || { echo "timed out waiting for the user session" >&2; return 1; }
        sleep 3
    done
}

wait_session_painted() {
    # graphical-session.target goes active before the shell has drawn
    # anything — a screendump taken right away catches a grey void. The
    # shell processes coming up is the assertable half; the settle after
    # covers first-frame latency, which nothing exposes to poll on.
    local deadline=$((SECONDS + ${1:-120}))
    until tssh 'pgrep -x cosmic-panel >/dev/null && pgrep -x cosmic-bg >/dev/null' 2>/dev/null; do
        ((SECONDS < deadline)) || { echo "timed out waiting for the shell to paint" >&2; return 1; }
        sleep 3
    done
    sleep "${TOPAZ_TEST_PAINT_SETTLE:-10}"
}

run_suite() {
    # A bare name resolves under tests/suites/; a path to a suite file is
    # run as-is, so a companion repo can ride this harness with its own
    # suite. TESTS_DIR is passed down for the suite to source lib.sh.
    local name="$1" script="$TESTS_DIR/suites/$1.sh"
    [[ -f "$script" ]] || script="$name"
    [[ -f "$script" ]] || { echo "no such suite: $name" >&2; return 2; }
    TESTS_DIR="$TESTS_DIR" bash "$script"
}

# --- suite assertion helpers (same output shape as topaz check) -------------

checks=0
fails=0

check() { # check <description> <command...>
    local desc="$1"
    shift
    checks=$((checks + 1))
    if "$@" >/dev/null 2>&1; then
        printf '[ ok ] %s\n' "$desc"
    else
        printf '[FAIL] %s\n' "$desc"
        fails=$((fails + 1))
    fi
}

check_not() { # check_not <description> <command that must fail>
    local desc="$1"
    shift
    checks=$((checks + 1))
    if "$@" >/dev/null 2>&1; then
        printf '[FAIL] %s\n' "$desc"
        fails=$((fails + 1))
    else
        printf '[ ok ] %s\n' "$desc"
    fi
}

is_empty() { [[ -z "$("$@" 2>/dev/null | tr -d '[:space:]')" ]]; }

contains() { printf '%s' "$1" | grep -qF "$2"; }

suite_verdict() {
    printf '%s: %d/%d checks passed\n' "$1" "$((checks - fails))" "$checks"
    [[ "$fails" -eq 0 ]]
}
